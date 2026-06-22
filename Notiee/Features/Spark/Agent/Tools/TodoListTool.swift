import Foundation

@MainActor
final class TodoListTool: AgentTool {
    let name = "todo_list"
    let description = "列出用户的待办事项，可按状态筛选"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "status": AgentToolProperty(type: "string", description: "筛选状态：all=全部，pending=未完成，completed=已完成", enumValues: ["all", "pending", "completed"], items: nil),
            "record_id": AgentToolProperty(type: "string", description: "筛选特定拍记的待办（可选）", enumValues: nil, items: nil)
        ],
        required: []
    )

    let recordManager: RecordManager

    init(recordManager: RecordManager) {
        self.recordManager = recordManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        let status = parameters["status"] as? String ?? "all"
        let recordIDStr = parameters["record_id"] as? String

        var todos = recordManager.todos
        if let rid = recordIDStr, let uuid = UUID(uuidString: rid) {
            todos = todos.filter { $0.recordID == uuid }
        }
        switch status {
        case "pending": todos = todos.filter { !$0.isCompleted }
        case "completed": todos = todos.filter { $0.isCompleted }
        default: break
        }

        let todosData = todos.map { todo -> [String: Any] in
            [
                "id": todo.id.uuidString,
                "content": todo.content,
                "is_completed": todo.isCompleted,
                "due_date": todo.dueDate?.ISO8601Format() ?? NSNull(),
                "has_reminder": todo.hasReminder,
                "record_id": todo.recordID?.uuidString ?? NSNull()
            ]
        }

        let message = todos.isEmpty
            ? "当前没有待办事项。"
            : "找到 \(todos.count) 条待办事项：\n" + todos.enumerated().map {
                "  [\($0+1)] \($1.isCompleted ? "✓" : "◌") \($1.content)"
            }.joined(separator: "\n")

        return AgentToolResult(success: true, message: message, data: ["todos": todosData], undoAction: nil)
    }
}
