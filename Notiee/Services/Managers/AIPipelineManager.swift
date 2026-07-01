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

        let service = aiService
        let resolvedTitle = eventTitle

        Task { [weak self, weak access] in
            guard let self else { return }

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
                await MainActor.run {
                    access?.setProcessingState(.failed, for: recordID)
                    access?.persistRecords()
                    print("AI Processing failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
