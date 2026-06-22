import Foundation

@MainActor
final class TodoCompleteTool: AgentTool {
    let name = "todo_complete"
    let description = "完成或取消完成一条待办事项"
    let permission: AgentToolPermission = .write

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "todo_id": AgentToolProperty(type: "string", description: "待办事项ID", enumValues: nil, items: nil),
            "completed": AgentToolProperty(type: "boolean", description: "true=完成，false=取消完成", enumValues: nil, items: nil)
        ],
        required: ["todo_id", "completed"]
    )

    let recordManager: RecordManager

    init(recordManager: RecordManager) {
        self.recordManager = recordManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let todoIDStr = parameters["todo_id"] as? String,
              let todoID = UUID(uuidString: todoIDStr),
              let completed = parameters["completed"] as? Bool else {
            throw AgentToolError.missingParameter("todo_id/completed")
        }
        guard let todo = recordManager.todos.first(where: { $0.id == todoID }) else {
            return AgentToolResult(success: false, message: "未找到待办 \(todoIDStr)", data: nil, undoAction: nil)
        }

        let wasCompleted = todo.isCompleted

        if wasCompleted != completed {
            recordManager.toggleTodo(id: todoID)
        }

        let action = completed ? "完成" : "取消完成"
        return AgentToolResult(
            success: true,
            message: "已\(action)待办「\(todo.content)」",
            data: nil,
            undoAction: AgentUndoAction(
                toolName: "todo_complete",
                description: "将待办「\(todo.content)」恢复为\(wasCompleted ? "已完成" : "未完成")",
                undoParameters: ["todo_id": todo.id.uuidString, "completed": wasCompleted],
                snapshotPath: nil
            )
        )
    }
}
