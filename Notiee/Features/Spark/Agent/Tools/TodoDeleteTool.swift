import Foundation

@MainActor
final class TodoDeleteTool: AgentTool {
    let name = "todo_delete"
    let description = "删除指定待办（撤销专用，模型不可直接调用）"
    let permission: AgentToolPermission = .destructive
    var visibleToModel: Bool { false }

    let parametersSchema = AgentToolParametersSchema(
        properties: ["todo_id": AgentToolProperty(type: "string", description: "要删除的待办UUID", enumValues: nil, items: nil)],
        required: ["todo_id"]
    )

    let recordManager: RecordManager
    init(recordManager: RecordManager) { self.recordManager = recordManager }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let idStr = parameters["todo_id"] as? String, let id = UUID(uuidString: idStr) else {
            throw AgentToolError.missingParameter("todo_id")
        }
        recordManager.deleteTodo(id: id)
        return AgentToolResult(success: true, message: "已删除待办", data: nil, undoAction: nil)
    }
}
