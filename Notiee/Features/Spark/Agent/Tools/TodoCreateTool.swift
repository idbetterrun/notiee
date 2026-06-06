import Foundation

final class TodoCreateTool: AgentTool {
    let name = "todo_create"
    let description = "创建一条新的待办事项"
    let permission: AgentToolPermission = .write

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "content": AgentToolProperty(type: "string", description: "待办内容", enumValues: nil, items: nil),
            "record_id": AgentToolProperty(type: "string", description: "关联拍记ID（可选）", enumValues: nil, items: nil),
            "due_date": AgentToolProperty(type: "string", description: "截止日期 ISO8601 格式（可选）", enumValues: nil, items: nil),
            "has_reminder": AgentToolProperty(type: "boolean", description: "是否设置提醒（可选）", enumValues: nil, items: nil)
        ],
        required: ["content"]
    )

    let recordManager: RecordManager

    init(recordManager: RecordManager) {
        self.recordManager = recordManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let content = parameters["content"] as? String else {
            throw AgentToolError.missingParameter("content")
        }
        let recordID = (parameters["record_id"] as? String).flatMap(UUID.init(uuidString:))
        let dueDate: Date? = {
            if let dateStr = parameters["due_date"] as? String {
                return ISO8601DateFormatter().date(from: dateStr)
            }
            return nil
        }()
        let hasReminder = parameters["has_reminder"] as? Bool ?? false

        let todo = NoteTodo(recordID: recordID, content: content, dueDate: dueDate, hasReminder: hasReminder)
        recordManager.addTodo(todo)

        return AgentToolResult(
            success: true,
            message: "已创建待办「\(content)」",
            data: ["todo_id": todo.id.uuidString],
            undoAction: AgentUndoAction(
                toolName: "todo_delete",
                description: "删除待办「\(content)」",
                undoParameters: ["todo_id": todo.id.uuidString],
                snapshotPath: nil
            )
        )
    }
}
