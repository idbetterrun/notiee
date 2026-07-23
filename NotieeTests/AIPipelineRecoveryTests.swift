import XCTest
@testable import Notiee

@MainActor
final class SpyProcessingResultNotifier: ProcessingResultNotifying {
    var calls: [(UUID, AIProcessingState)] = []
    var shouldReturn: Bool = true

    func notify(recordID: UUID, outcome: AIProcessingState) async -> Bool {
        calls.append((recordID, outcome))
        return shouldReturn
    }
}

@MainActor
final class RecordingScheduler: AIProcessingScheduling {
    var scheduleCallCount = 0
    private var registeredHandler: (() async -> Void)?

    func register(handler: @escaping () async -> Void) {
        registeredHandler = handler
    }

    func scheduleProcessing() {
        scheduleCallCount += 1
    }

    func runRegisteredHandler() async {
        await registeredHandler?()
    }
}

@MainActor
final class AIPipelineRecoveryTests: XCTestCase {

    func testRetryFailedRecord_reenqueuesAndCompletes() async throws {
        let record = NoteRecord(localImagePaths: ["retry"], processingState: .failed)
        let store = makeStore(records: [record])

        store.retryAIProcessing(for: record.id)
        try await waitUntil { store.record(id: record.id)?.processingState == .completed }

        XCTAssertEqual(store.record(id: record.id)?.processingState, .completed)
    }

    func testResumePendingAIProcessing_recoversInterruptedRecord() async throws {
        let record = NoteRecord(localImagePaths: ["interrupted"], processingState: .processing)
        let store = makeStore(records: [record])

        await store.resumePendingAIProcessing()

        XCTAssertEqual(store.record(id: record.id)?.processingState, .completed)
    }

    func testProcessingNotification_completed_deliversNotification() async throws {
        let notifier = SpyProcessingResultNotifier()
        let record = NoteRecord(
            localImagePaths: ["test-notify"],
            processingState: .pending,
            processingNotificationState: .requested
        )
        let store = makeStore(records: [record], notifier: notifier)

        store.processImportedScreenshot(recordID: record.id)
        try await waitUntil { store.record(id: record.id)?.processingState == .completed }

        XCTAssertEqual(notifier.calls.count, 1)
        XCTAssertEqual(notifier.calls.first?.0, record.id)
        XCTAssertEqual(notifier.calls.first?.1, .completed)
        XCTAssertEqual(store.record(id: record.id)?.processingNotificationState, .delivered)
    }

    func testProcessingNotification_failed_retainsImagesAndNotifies() async throws {
        let notifier = SpyProcessingResultNotifier()
        let record = NoteRecord(
            localImagePaths: ["test-fail"],
            processingState: .pending,
            processingNotificationState: .requested
        )
        let store = makeStore(records: [record], notifier: notifier)

        store.processImportedScreenshot(recordID: record.id)
        try await waitUntil { store.record(id: record.id)?.processingState == .failed }

        XCTAssertEqual(notifier.calls.count, 1)
        XCTAssertEqual(notifier.calls.first?.0, record.id)
        XCTAssertEqual(notifier.calls.first?.1, .failed)
        XCTAssertEqual(store.record(id: record.id)?.localImagePaths, ["test-fail"])
        XCTAssertEqual(store.record(id: record.id)?.processingNotificationState, .delivered)
    }

    func testRuntimeSchedulesAndRunsPendingProcessing() async throws {
        let scheduler = RecordingScheduler()
        let store = makeStore(records: [NoteRecord(localImagePaths: ["pending"])])
        let runtime = NotieeProcessingRuntime(store: store, scheduler: scheduler)

        runtime.scheduleProcessing()
        await scheduler.runRegisteredHandler()

        XCTAssertEqual(scheduler.scheduleCallCount, 1)
        XCTAssertEqual(store.records.first?.processingState, .completed)
    }

    private func makeStore(
        records: [NoteRecord],
        notifier: (any ProcessingResultNotifying)? = nil
    ) -> NotieeStore {
        NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: records,
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL()),
            aiService: MockAIProcessingService(processingDelay: 0.01...0.02),
            autoProcess: false,
            notifier: notifier
        )
    }

    private func waitUntil(timeout: TimeInterval = 5, poll: TimeInterval = 0.1, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: UInt64(poll * 1_000_000_000))
        }
        throw NSError(domain: "AIPipelineRecoveryTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "waitUntil timed out"])
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private var referenceDate: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        components.year = 2026
        components.month = 5
        components.day = 21
        components.hour = 10
        components.minute = 30
        return components.date!
    }
}
