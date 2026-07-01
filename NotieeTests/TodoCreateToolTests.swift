import XCTest
@testable import Notiee

@MainActor
final class TodoCreateToolTests: XCTestCase {

    private func makeRecordManager() -> RecordManager {
        RecordManager(
            records: [],
            todos: [],
            recordStore: JSONNoteRecordStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")),
            todoStore: JSONNoteTodoStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        )
    }

    // Regression: date_info returns yyyy-MM-dd, which the tool must accept.
    func testCreate_withYearMonthDayDueDate_setsDueDate() async throws {
        let mgr = makeRecordManager()
        let tool = TodoCreateTool(recordManager: mgr)
        let result = try await tool.execute(parameters: [
            "content": "交作业",
            "due_date": "2026-06-26"
        ])
        XCTAssertTrue(result.success)
        let todo = mgr.todos.first { $0.content == "交作业" }
        XCTAssertNotNil(todo)
        XCTAssertEqual(todo?.dueDate, CalendarQueryTool.parseDate("2026-06-26"))
    }

    func testCreate_withISO8601DueDate_setsDueDate() async throws {
        let mgr = makeRecordManager()
        let tool = TodoCreateTool(recordManager: mgr)
        _ = try await tool.execute(parameters: [
            "content": "开会",
            "due_date": "2026-06-26T09:00:00Z"
        ])
        let todo = mgr.todos.first { $0.content == "开会" }
        XCTAssertNotNil(todo?.dueDate)
    }

    func testCreate_withoutDueDate_leavesNil() async throws {
        let mgr = makeRecordManager()
        let tool = TodoCreateTool(recordManager: mgr)
        _ = try await tool.execute(parameters: ["content": "随手记"])
        let todo = mgr.todos.first { $0.content == "随手记" }
        XCTAssertNotNil(todo)
        XCTAssertNil(todo?.dueDate)
    }

    func testCreate_missingContent_throws() async {
        let mgr = makeRecordManager()
        let tool = TodoCreateTool(recordManager: mgr)
        do {
            _ = try await tool.execute(parameters: ["due_date": "2026-06-26"])
            XCTFail("缺 content 应抛错")
        } catch let e as AgentToolError {
            XCTAssertEqual(e.errorDescription, "缺少必要参数：content")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
