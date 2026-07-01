import XCTest
@testable import Notiee

@MainActor
final class MockAIProcessingServiceTests: XCTestCase {

    func testProcessReturnsResultForAnyEventTitle() async throws {
        let service = MockAIProcessingService(processingDelay: 0.01...0.02)
        let result = try await service.process(imagePaths: ["test"], eventTitle: "任意课程名称")

        XCTAssertFalse(result.title.isEmpty)
        XCTAssertFalse(result.ocrText.isEmpty)
        XCTAssertFalse(result.summary.isEmpty)
        XCTAssertFalse(result.todos.isEmpty)
    }

    func testProcessReturnsResultForNilEvent() async throws {
        let service = MockAIProcessingService(processingDelay: 0.01...0.02)
        let result = try await service.process(imagePaths: ["test"], eventTitle: nil)

        XCTAssertFalse(result.title.isEmpty)
        XCTAssertFalse(result.summary.isEmpty)
    }

    func testProcessThrowsOnFailPath() async {
        let service = MockAIProcessingService(processingDelay: 0.01...0.02)
        do {
            _ = try await service.process(imagePaths: ["fail"], eventTitle: nil)
            XCTFail("Expected error for fail path")
        } catch {
            XCTAssertEqual((error as NSError).code, 500)
        }
    }

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

        let record = store.capturePhoto(localImagePaths: ["test-photo"])
        XCTAssertEqual(record.processingState, .pending)

        try await Task.sleep(for: .seconds(2))
        let updatedRecord = store.records.first { $0.id == record.id }
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

        let record = store.capturePhoto(localImagePaths: ["test-complete"])

        try await Task.sleep(for: .seconds(3))

        let completed = store.records.first { $0.id == record.id }!
        XCTAssertEqual(completed.processingState, .completed)
        XCTAssertFalse(completed.ocrText.isEmpty)
        XCTAssertFalse(completed.summary.isEmpty)
        XCTAssertNotEqual(completed.title, "待提取内容")
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

        let record = store.capturePhoto(localImagePaths: ["test-todos"])

        try await Task.sleep(for: .seconds(3))

        let todosForRecord = store.todos(for: store.records.first { $0.id == record.id }!)
        XCTAssertFalse(todosForRecord.isEmpty)
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

        let record = store.capturePhoto(localImagePaths: ["no-auto"])
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

        let record = store.capturePhoto(localImagePaths: ["manual"])
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

        let record = store.capturePhoto(localImagePaths: ["update-test"])
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
