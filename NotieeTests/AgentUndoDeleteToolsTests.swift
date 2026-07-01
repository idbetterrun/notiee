import XCTest
@testable import Notiee

@MainActor
final class AgentUndoDeleteToolsTests: XCTestCase {
    private func makeManager(_ records: [NoteRecord], _ todos: [NoteTodo]) -> RecordManager {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID()).json")
        return RecordManager(
            records: records, todos: todos,
            recordStore: JSONNoteRecordStore(fileURL: url),
            todoStore: JSONNoteTodoStore(fileURL: url.appendingPathExtension("todos")))
    }

    func testNoteDeleteTool_removesRecord() async throws {
        let rec = NoteRecord(localImagePaths: [], title: "t", processingState: .completed)
        let mgr = makeManager([rec], [])
        let tool = NoteDeleteTool(recordManager: mgr)

        let result = try await tool.execute(parameters: ["record_id": rec.id.uuidString])

        XCTAssertTrue(result.success)
        XCTAssertFalse(mgr.records.contains { $0.id == rec.id })
    }

    func testTodoDeleteTool_removesTodo() async throws {
        let todo = NoteTodo(recordID: nil, content: "x")
        let mgr = makeManager([], [todo])
        let tool = TodoDeleteTool(recordManager: mgr)

        let result = try await tool.execute(parameters: ["todo_id": todo.id.uuidString])

        XCTAssertTrue(result.success)
        XCTAssertFalse(mgr.todos.contains { $0.id == todo.id })
    }

    func testDeleteTools_areHiddenFromModel() {
        let rec = makeManager([], [])
        let registry = AgentToolRegistry(tools: [
            NoteDeleteTool(recordManager: rec),
            TodoDeleteTool(recordManager: rec)
        ])
        XCTAssertNotNil(registry.get("note_delete"))
        let modelNames = registry.allTools(for: .full).map { $0.name }
        XCTAssertFalse(modelNames.contains("note_delete"))
        XCTAssertFalse(modelNames.contains("todo_delete"))
    }
}
