import Foundation

/// Protocol through which AIPipelineManager reads and mutates records during processing.
protocol AIPipelineRecordAccess: AnyObject {
    func record(id: UUID) -> NoteRecord?
    func setProcessingState(_ state: AIProcessingState, for recordID: UUID)
    func incrementRetryCount(for recordID: UUID)
    func applyAIResult(_ result: AIProcessingResult, to recordID: UUID)
    func persistRecords()
    func recordsNeedingAIRecovery() -> [NoteRecord]
    func setProcessingNotificationState(_ state: ProcessingNotificationState, for recordID: UUID)
    func eventTitle(for recordID: UUID) -> String?
}

@MainActor
protocol ProcessingResultNotifying: Sendable {
    func notify(recordID: UUID, outcome: AIProcessingState) async -> Bool
}

@MainActor
final class AIPipelineManager {
    let aiService: any AIProcessingService
    let settingsStore: AppSettingsPersisting

    weak var recordAccess: AIPipelineRecordAccess?
    var notifier: (any ProcessingResultNotifying)?
    private var inFlightRecordIDs = Set<UUID>()

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

    func retryAndEnqueue(recordID: UUID, eventTitle: String?) {
        guard let access = recordAccess,
              let record = access.record(id: recordID),
              record.processingState == .failed || record.processingState == .deadLetter else { return }

        access.setProcessingState(.pending, for: recordID)
        access.persistRecords()

        enqueueProcessing(
            recordID: recordID,
            localImagePaths: record.localImagePaths,
            eventTitle: eventTitle
        )
    }

    func enqueueProcessing(
        recordID: UUID,
        localImagePaths: [String],
        eventTitle: String?
    ) {
        Task { [weak self] in
            await self?.process(
                recordID: recordID,
                localImagePaths: localImagePaths,
                eventTitle: eventTitle
            )
        }
    }

    func resumePendingProcessing() async {
        guard let access = recordAccess else { return }

        for record in access.recordsNeedingAIRecovery()
        where record.processingState == .processing {
            access.setProcessingState(.pending, for: record.id)
        }

        for record in access.recordsNeedingAIRecovery()
        where record.processingState == .pending {
            await process(
                recordID: record.id,
                localImagePaths: record.localImagePaths,
                eventTitle: access.eventTitle(for: record.id)
            )
        }
    }

    // MARK: - Private

    private func process(recordID: UUID, localImagePaths: [String], eventTitle: String?) async {
        guard !inFlightRecordIDs.contains(recordID) else { return }
        inFlightRecordIDs.insert(recordID)
        defer { inFlightRecordIDs.remove(recordID) }

        guard let access = recordAccess else { return }
        guard aiEnabled else {
            access.setProcessingState(.failed, for: recordID)
            access.persistRecords()
            await deliverNotificationIfRequested(recordID: recordID, outcome: .failed, access: access)
            return
        }

        access.setProcessingState(.processing, for: recordID)
        access.persistRecords()

        do {
            let result = try await aiService.process(
                imagePaths: localImagePaths,
                eventTitle: eventTitle
            )
            access.applyAIResult(result, to: recordID)
            access.persistRecords()
            await deliverNotificationIfRequested(recordID: recordID, outcome: .completed, access: access)
        } catch {
            access.setProcessingState(.failed, for: recordID)
            access.persistRecords()
            await deliverNotificationIfRequested(recordID: recordID, outcome: .failed, access: access)
            print("AI Processing failed: \(error.localizedDescription)")
        }
    }

    private func deliverNotificationIfRequested(
        recordID: UUID,
        outcome: AIProcessingState,
        access: AIPipelineRecordAccess
    ) async {
        guard let record = access.record(id: recordID),
              record.processingNotificationState == .requested,
              let notifier = notifier else { return }
        let delivered = await notifier.notify(recordID: recordID, outcome: outcome)
        if delivered {
            access.setProcessingNotificationState(.delivered, for: recordID)
            access.persistRecords()
        }
    }
}
