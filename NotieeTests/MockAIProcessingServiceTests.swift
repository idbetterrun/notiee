import XCTest
@testable import Notiee

@MainActor
final class MockAIProcessingServiceTests: XCTestCase {

    // MARK: - MockAIProcessingService Unit Tests

    func testGenerateReturnsMatchingResultForMathEvent() {
        let service = MockAIProcessingService()
        let result = service.generate(for: "高等数学")

        XCTAssertFalse(result.title.isEmpty)
        XCTAssertFalse(result.ocrText.isEmpty)
        XCTAssertFalse(result.summary.isEmpty)
        XCTAssertFalse(result.todos.isEmpty)
    }

    func testGenerateReturnsMatchingResultForDesignEvent() {
        let service = MockAIProcessingService()
        let result = service.generate(for: "产品设计课")

        XCTAssertFalse(result.title.isEmpty)
        XCTAssertFalse(result.summary.isEmpty)
    }

    func testGenerateReturnsFallbackForUnknownEvent() {
        let service = MockAIProcessingService()
        let result = service.generate(for: "完全未知的活动名称 XYZ")

        XCTAssertFalse(result.title.isEmpty)
        XCTAssertFalse(result.ocrText.isEmpty)
    }

    func testGenerateReturnsFallbackForNilEvent() {
        let service = MockAIProcessingService()
        let result = service.generate(for: nil)

        XCTAssertFalse(result.title.isEmpty)
        XCTAssertFalse(result.summary.isEmpty)
    }

    // MARK: - NotieeStore AI Pipeline Integration Tests

    func testCapturePhotoWithAutoProcessTransitionsToProcessing() async throws {
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL()),
            aiService: MockAIProcessingService(processingDelay: 0.1...0.2),
            autoProcess: true
        )

        let record = store.capturePhoto(localImagePath: "mock://test")
        XCTAssertEqual(record.processingState, .pending)

        // Wait for Phase 1: pending → processing
        try await Task.sleep(for: .seconds(2))
        let updatedRecord = store.records.first { $0.id == record.id }
        // By now it should be either .processing or .completed
        XCTAssertNotEqual(updatedRecord?.processingState, .pending)
    }

    func testCapturePhotoWithAutoProcessCompletesAndFillsData() async throws {
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL()),
            aiService: MockAIProcessingService(processingDelay: 0.1...0.2),
            autoProcess: true
        )

        let record = store.capturePhoto(localImagePath: "mock://test-complete")

        // Wait enough for both phases to complete
        try await Task.sleep(for: .seconds(3))

        let completed = store.records.first { $0.id == record.id }!
        XCTAssertEqual(completed.processingState, .completed)
        XCTAssertFalse(completed.ocrText.isEmpty, "OCR text should be filled after processing")
        XCTAssertFalse(completed.summary.isEmpty, "Summary should be filled after processing")
        XCTAssertNotEqual(completed.title, "未分类拍记", "Title should be updated by AI")
    }

    func testCapturePhotoWithAutoProcessAddsTodos() async throws {
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL()),
            aiService: MockAIProcessingService(processingDelay: 0.1...0.2),
            autoProcess: true
        )

        let record = store.capturePhoto(localImagePath: "mock://test-todos")

        // Wait for full pipeline
        try await Task.sleep(for: .seconds(3))

        let todosForRecord = store.todos(for: store.records.first { $0.id == record.id }!)
        XCTAssertFalse(todosForRecord.isEmpty, "AI should have extracted todos for this record")
    }

    func testCapturePhotoWithoutAutoProcessStaysPending() {
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL()),
            autoProcess: false
        )

        let record = store.capturePhoto(localImagePath: "mock://no-auto")
        XCTAssertEqual(record.processingState, .pending)
        XCTAssertEqual(store.records.first?.processingState, .pending)
    }

    func testManualProcessRecordTriggersProcessing() async throws {
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL()),
            aiService: MockAIProcessingService(processingDelay: 0.1...0.2),
            autoProcess: false
        )

        let record = store.capturePhoto(localImagePath: "mock://manual")
        XCTAssertEqual(record.processingState, .pending)

        store.processRecord(record)
        try await Task.sleep(for: .seconds(3))

        let processed = store.records.first { $0.id == record.id }!
        XCTAssertEqual(processed.processingState, .completed)
        XCTAssertFalse(processed.summary.isEmpty)
    }

    func testUpdateRecordMutatesExistingRecord() {
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )

        let record = store.capturePhoto(localImagePath: "mock://update-test")
        var updated = record
        updated.summary = "手动更新的摘要"
        store.updateRecord(updated)

        XCTAssertEqual(store.records.first?.summary, "手动更新的摘要")
    }

    func testAddTodoAppendsToTodosList() {
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )

        let todo = NoteTodo(recordID: nil, content: "测试待办事项")
        store.addTodo(todo)

        XCTAssertEqual(store.todos.count, 1)
        XCTAssertEqual(store.todos.first?.content, "测试待办事项")
    }

    // MARK: - Helpers

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
