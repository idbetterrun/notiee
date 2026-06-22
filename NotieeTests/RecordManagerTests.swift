import XCTest
@testable import Notiee

@MainActor
final class RecordManagerTests: XCTestCase {

    // MARK: - capturePhoto

    func testCapturePhotoStoresRecordAndPersists() throws {
        let persistence = recordStore()
        let store = makeStore(store: persistence)
        let record = store.capturePhoto(
            localImagePaths: ["test-photo"],
            eventID: UUID(),
            eventTitle: "测试课程",
            capturedAt: ref
        )

        XCTAssertEqual(store.records, [record])
        XCTAssertEqual(record.title, "测试课程 拍记")
        XCTAssertEqual(try persistence.loadRecords(), [record])
        XCTAssertNil(store.lastPersistenceError)
    }

    func testCapturePhotoWithoutEventTitle() {
        let store = makeStore()
        let record = store.capturePhoto(
            localImagePaths: ["img"],
            eventID: nil,
            eventTitle: nil,
            capturedAt: ref
        )
        XCTAssertEqual(record.title, "未分类拍记")
    }

    func testCapturePhotoInsertsAtFront() {
        let store = makeStore(records: [makeRecord(title: "Existing", capturedAt: ref)])
        let record = store.capturePhoto(
            localImagePaths: ["img"],
            eventID: nil,
            eventTitle: nil,
            capturedAt: ref
        )
        XCTAssertEqual(store.records.first?.id, record.id)
        XCTAssertEqual(store.records.count, 2)
    }

    // MARK: - sortedRecords

    func testSortedRecordsFiltersDeleted() {
        let active = makeRecord(title: "Active")
        let deleted = makeRecord(title: "Deleted", isDeleted: true)
        let store = makeStore(records: [active, deleted])
        XCTAssertEqual(store.sortedRecords.map(\.title), ["Active"])
    }

    func testSortedRecordsNewestFirst() {
        let older = makeRecord(title: "Older", capturedAt: ref.addingTimeInterval(-60))
        let newer = makeRecord(title: "Newer", capturedAt: ref)
        let store = makeStore(records: [older, newer])
        XCTAssertEqual(store.sortedRecords.map(\.title), ["Newer", "Older"])
    }

    // MARK: - favoriteRecords / deletedRecords

    func testFavoriteRecords() {
        let fav = makeRecord(title: "Fav", isFavorite: true)
        let normal = makeRecord(title: "Normal")
        let store = makeStore(records: [fav, normal])
        XCTAssertEqual(store.favoriteRecords.map(\.title), ["Fav"])
    }

    func testDeletedRecords() {
        let deleted = makeRecord(title: "D", isDeleted: true)
        let active = makeRecord(title: "A")
        let store = makeStore(records: [deleted, active])
        XCTAssertEqual(store.deletedRecords.map(\.title), ["D"])
    }

    // MARK: - Counts

    func testUncategorizedCount() {
        let withEvent = makeRecord(eventID: UUID())
        let without = makeRecord(eventID: nil)
        let store = makeStore(records: [withEvent, without])
        XCTAssertEqual(store.uncategorizedCount, 1)
    }

    func testPendingRecordsCount() {
        let pending = makeRecord(processingState: .pending)
        let completed = makeRecord(processingState: .completed)
        let store = makeStore(records: [pending, completed])
        XCTAssertEqual(store.pendingRecordsCount, 1)
    }

    // MARK: - todayRecords

    func testTodayRecords() {
        let today = makeRecord(capturedAt: ref)
        let yesterday = makeRecord(capturedAt: ref.addingTimeInterval(-86400))
        let store = makeStore(records: [today, yesterday])
        XCTAssertEqual(store.todayRecords(relativeTo: ref).count, 1)
    }

    // MARK: - records(in:)

    func testRecordsInRangeToday() {
        let today = makeRecord(capturedAt: ref)
        let yesterday = makeRecord(capturedAt: ref.addingTimeInterval(-86400))
        let store = makeStore(records: [today, yesterday])
        XCTAssertEqual(store.records(in: TimeRange.today, relativeTo: ref).count, 1)
    }

    func testRecordsInRangeLast7Days() {
        let recent = makeRecord(capturedAt: ref.addingTimeInterval(-3 * 86400))
        let old = makeRecord(capturedAt: ref.addingTimeInterval(-10 * 86400))
        let store = makeStore(records: [recent, old])
        XCTAssertEqual(store.records(in: .last7Days, relativeTo: ref).count, 1)
    }

    // MARK: - totalTokens

    func testTotalTokens() {
        let r1 = makeRecord(capturedAt: ref, tokenUsage: 100)
        let r2 = makeRecord(capturedAt: ref, tokenUsage: 200)
        let store = makeStore(records: [r1, r2])
        XCTAssertEqual(store.totalTokens(in: TimeRange.today, relativeTo: ref), 300)
    }

    func testTotalTokensIncludeDeleted() {
        let active = makeRecord(capturedAt: ref, tokenUsage: 100)
        let deleted = makeRecord(capturedAt: ref, isDeleted: true, tokenUsage: 50)
        let store = makeStore(records: [active, deleted])
        let total = store.totalTokens(in: TimeRange.today, includeDeleted: true, relativeTo: ref)
        XCTAssertEqual(total, 150)
    }

    // MARK: - topRecordsByToken

    func testTopRecordsByToken() {
        let low = makeRecord(capturedAt: ref, tokenUsage: 10)
        let high = makeRecord(capturedAt: ref, tokenUsage: 100)
        let store = makeStore(records: [low, high])
        let top = store.topRecordsByToken(in: TimeRange.today, limit: 1, relativeTo: ref)
        XCTAssertEqual(top.first?.tokenUsage, 100)
    }

    // MARK: - records(matching:)

    func testRecordsMatchingSearchesTitleSummaryOCR() {
        let r1 = makeRecord(title: "白板：旅程图", ocrText: "persona journey map", summary: "课堂记录")
        let r2 = makeRecord(title: "竞品截图", ocrText: "benchmark", summary: "补充journey对比")
        let store = makeStore(records: [r1, r2])
        XCTAssertEqual(store.records(matching: "journey").count, 2)
        XCTAssertEqual(store.records(matching: "截图").count, 1)
        XCTAssertEqual(store.records(matching: "").count, 2)
    }

    // MARK: - toggleFavorite / toggleDeleted

    func testToggleFavorite() {
        let record = makeRecord(title: "Test")
        let store = makeStore(records: [record])
        store.toggleFavorite(id: record.id)
        XCTAssertTrue(store.records.first?.isFavorite ?? false)
    }

    func testToggleDeletedAccumulatesTokens() {
        let current = UserDefaults.standard.integer(forKey: UDK.accumulatedDeletedTokens)
        let record = makeRecord(capturedAt: ref, tokenUsage: 42)
        let store = makeStore(records: [record])
        store.toggleDeleted(id: record.id)
        XCTAssertTrue(store.records.first?.isDeleted ?? false)
        let after = UserDefaults.standard.integer(forKey: UDK.accumulatedDeletedTokens)
        XCTAssertEqual(after, current + 42)
    }

    // MARK: - permanentlyDelete

    func testPermanentlyDeleteRemovesRecordAndTodos() {
        var record = makeRecord(title: "ToDelete")
        let todo = NoteTodo(recordID: record.id, content: "Test todo")
        let store = makeStore(records: [record], todos: [todo])
        store.permanentlyDelete(id: record.id)
        XCTAssertTrue(store.records.isEmpty)
        XCTAssertTrue(store.todos.isEmpty)
    }

    // MARK: - updateRecordEvent

    func testUpdateRecordEvent() {
        let eventID = UUID()
        let record = makeRecord(eventID: nil)
        let store = makeStore(records: [record])
        store.updateRecordEvent(recordID: record.id, newEventID: eventID)
        XCTAssertEqual(store.records.first?.eventID, eventID)
    }

    // MARK: - assignRecordToFolder / clearFolderReferences

    func testAssignRecordToFolder() {
        let folderID = UUID()
        let record = makeRecord()
        let store = makeStore(records: [record])
        store.assignRecordToFolder(recordID: record.id, folderID: folderID)
        XCTAssertEqual(store.records.first?.folderID, folderID)
    }

    func testClearFolderReferences() {
        let folderID = UUID()
        let r1 = makeRecord(folderID: folderID)
        let r2 = makeRecord(folderID: folderID)
        let r3 = makeRecord(folderID: UUID())
        let store = makeStore(records: [r1, r2, r3])
        store.clearFolderReferences(for: folderID)
        XCTAssertEqual(store.records.filter { $0.folderID == nil }.count, 2)
        XCTAssertNotNil(store.records[2].folderID)
    }

    // MARK: - Todo mutations

    func testTodosForRecord() {
        let record = makeRecord()
        let t1 = NoteTodo(recordID: record.id, content: "First", createdAt: ref)
        let t2 = NoteTodo(recordID: record.id, content: "Second", createdAt: ref.addingTimeInterval(10))
        let t3 = NoteTodo(recordID: UUID(), content: "Other")
        let store = makeStore(records: [record], todos: [t1, t2, t3])
        let result = store.todos(for: record)
        XCTAssertEqual(result.map(\.content), ["First", "Second"])
    }

    func testToggleTodo() {
        let todo = NoteTodo(recordID: nil, content: "Task")
        let store = makeStore(todos: [todo])
        store.toggleTodo(id: todo.id)
        XCTAssertTrue(store.todos.first?.isCompleted ?? false)
    }

    func testUpdateTodoContent() {
        let todo = NoteTodo(recordID: nil, content: "Old")
        let store = makeStore(todos: [todo])
        store.updateTodoContent(id: todo.id, newContent: "New")
        XCTAssertEqual(store.todos.first?.content, "New")
    }

    func testDeleteTodo() {
        let todo = NoteTodo(recordID: nil, content: "Temp")
        let store = makeStore(todos: [todo])
        store.deleteTodo(id: todo.id)
        XCTAssertTrue(store.todos.isEmpty)
    }

    func testAddStandaloneTodo() {
        let store = makeStore()
        store.addStandaloneTodo(content: "Standalone", dueDate: nil, hasReminder: false)
        XCTAssertEqual(store.todos.first?.content, "Standalone")
        XCTAssertNil(store.todos.first?.recordID)
    }

    // MARK: - Persistence error

    func testLastPersistenceErrorIsNilOnSuccess() throws {
        let store = makeStore()
        store.capturePhoto(localImagePaths: ["img"], eventID: nil, eventTitle: nil, capturedAt: ref)
        XCTAssertNil(store.lastPersistenceError)
    }

    // MARK: - Helpers

    private var ref: Date {
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

    private func recordStore() -> JSONNoteRecordStore {
        JSONNoteRecordStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json"))
    }

    private func makeStore(
        records: [NoteRecord] = [],
        todos: [NoteTodo] = [],
        store: JSONNoteRecordStore? = nil
    ) -> RecordManager {
        RecordManager(
            records: records,
            todos: todos,
            recordStore: store ?? recordStore()
        )
    }

    private func makeRecord(
        id: UUID = UUID(),
        eventID: UUID? = nil,
        folderID: UUID? = nil,
        title: String = "Test Record",
        capturedAt: Date? = nil,
        isFavorite: Bool = false,
        isDeleted: Bool = false,
        tokenUsage: Int = 0,
        processingState: AIProcessingState = .completed,
        ocrText: String = "",
        summary: String = "",
        detailedContent: String = ""
    ) -> NoteRecord {
        NoteRecord(
            id: id,
            eventID: eventID,
            folderID: folderID,
            capturedAt: capturedAt ?? ref,
            localImagePaths: [],
            title: title,
            ocrText: ocrText,
            summary: summary,
            detailedContent: detailedContent,
            processingState: processingState,
            isFavorite: isFavorite,
            isDeleted: isDeleted,
            tokenUsage: tokenUsage
        )
    }
}
