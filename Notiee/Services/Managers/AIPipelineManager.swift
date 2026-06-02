import Foundation

/// Protocol through which AIPipelineManager reads and mutates records during processing.
protocol AIPipelineRecordAccess: AnyObject {
    func record(id: UUID) -> NoteRecord?
    func setProcessingState(_ state: AIProcessingState, for recordID: UUID)
    func incrementRetryCount(for recordID: UUID)
    func applyAIResult(_ result: AIProcessingResult, to recordID: UUID)
    func persistRecords()
}

@MainActor
final class AIPipelineManager {
    let aiService: any AIProcessingService
    let settingsStore: AppSettingsPersisting

    /// Weak reference to the record accessor (typically the Store).
    weak var recordAccess: AIPipelineRecordAccess?

    var aiEnabled: Bool {
        settingsStore.loadBool(forKey: UDK.aiEnabled, defaultValue: true)
    }

    var autoProcessAfterCapture: Bool {
        settingsStore.loadBool(forKey: UDK.autoProcessAfterCapture, defaultValue: true)
    }

    init(aiService: any AIProcessingService, settingsStore: AppSettingsPersisting) {
        self.aiService = aiService
        self.settingsStore = settingsStore
    }

    // MARK: - Entry Points

    /// Reset a failed/deadLetter record back to pending and re-enqueue.
    func retryAndEnqueue(recordID: UUID, eventTitle: String?) {
        guard let access = recordAccess,
              let record = access.record(id: recordID),
              record.processingState == .failed || record.processingState == .deadLetter else { return }

        // Reset retry count by applying a state change; the Store handles the rest.
        access.setProcessingState(.pending, for: recordID)
        access.persistRecords()

        enqueueProcessing(
            recordID: recordID,
            localImagePaths: record.localImagePaths,
            eventTitle: eventTitle,
            retryCount: 0
        )
    }

    /// Enqueue a record for AI processing.
    func enqueueProcessing(
        recordID: UUID,
        localImagePaths: [String],
        eventTitle: String?,
        retryCount: Int? = nil
    ) {
        guard aiEnabled, let access = recordAccess else { return }

        let actualRetryCount = retryCount ?? 0
        let maxRetries = 4
        let delaySeconds: UInt64 = {
            switch actualRetryCount {
            case 0: return 0
            case 1: return 2_000_000_000
            case 2: return 4_000_000_000
            case 3: return 8_000_000_000
            default: return 0
            }
        }()

        let service = aiService
        let resolvedTitle = eventTitle

        Task { [weak self, weak access] in
            guard let self else { return }

            if delaySeconds > 0 {
                try? await Task.sleep(nanoseconds: delaySeconds)
            }

            await MainActor.run {
                access?.setProcessingState(.processing, for: recordID)
                access?.persistRecords()
            }

            do {
                let result = try await service.process(
                    imagePaths: localImagePaths,
                    eventTitle: resolvedTitle
                )
                await MainActor.run {
                    access?.applyAIResult(result, to: recordID)
                    access?.persistRecords()
                }
            } catch {
                let nextRetry = actualRetryCount + 1
                await MainActor.run {
                    if nextRetry >= maxRetries {
                        access?.setProcessingState(.deadLetter, for: recordID)
                        access?.persistRecords()
                        print("AI Processing dead letter after \(maxRetries) retries: \(error.localizedDescription)")
                    } else {
                        access?.incrementRetryCount(for: recordID)
                        access?.setProcessingState(.failed, for: recordID)
                        access?.persistRecords()
                        print("AI Processing failed (retry \(nextRetry)/\(maxRetries)): \(error.localizedDescription)")

                        // Re-trigger pipeline with incremented count
                        Task { @MainActor [weak self] in
                            self?.enqueueProcessing(
                                recordID: recordID,
                                localImagePaths: localImagePaths,
                                eventTitle: resolvedTitle,
                                retryCount: nextRetry
                            )
                        }
                    }
                }
            }
        }
    }
}
