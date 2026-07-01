import XCTest
@testable import Notiee

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testSampleDataIncludesCurrentEventAtReferenceDate() {
        let viewModel = TodayViewModel.sample(currentDate: referenceDate)

        XCTAssertEqual(viewModel.currentEvent?.title, "当前课程")
        XCTAssertEqual(viewModel.currentEvent?.status(at: referenceDate), .current)
    }

    func testPendingTodosExcludeCompletedItems() {
        let record = NoteRecord(
            id: UUID(),
            capturedAt: referenceDate,
            localImagePaths: ["test"],
            title: "测试",
            processingState: .completed
        )
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [record],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )
        let viewModel = TodayViewModel(store: store)

        store.addTodo(NoteTodo(recordID: record.id, content: "待办事项 1", createdAt: referenceDate))
        store.addTodo(NoteTodo(recordID: record.id, content: "待办事项 2", isCompleted: true, createdAt: referenceDate))

        XCTAssertEqual(viewModel.pendingTodos.map(\.content), ["待办事项 1"])
    }

    func testTodayRecordsAreFilteredAndNewestFirst() {
        let viewModel = TodayViewModel.sample(currentDate: referenceDate)

        XCTAssertTrue(viewModel.todayRecords.isEmpty)
    }

    func testTodayOverview_showsActionableCapsAndHidesFarFuture() {
        let store = NotieeStore(
            currentDate: Date(), events: [], todos: [], records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )
        let cal = Calendar.current
        let far = cal.date(byAdding: .day, value: 10, to: Date())!
        store.addTodo(NoteTodo(recordID: nil, content: "无截止"))
        store.addTodo(NoteTodo(recordID: nil, content: "远期", dueDate: far))

        let vm = TodayViewModel(store: store)
        let contents = vm.todayOverviewTodos.map { $0.content }
        XCTAssertTrue(contents.contains("无截止"))
        XCTAssertFalse(contents.contains("远期"), "远期待办不进 Today 概览")
    }

    func testTodayOverview_capsAtMaxCount() {
        let store = NotieeStore(
            currentDate: Date(), events: [], todos: [], records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )
        for i in 0..<10 { store.addTodo(NoteTodo(recordID: nil, content: "无截止\(i)")) }
        let vm = TodayViewModel(store: store)
        XCTAssertLessThanOrEqual(vm.todayOverviewTodos.count, TodayViewModel.overviewTodoCap)
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

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }
}
