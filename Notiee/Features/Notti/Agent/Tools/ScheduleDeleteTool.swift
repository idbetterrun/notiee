import Foundation

@MainActor
final class ScheduleDeleteTool: AgentTool {
    let name = "schedule_delete"
    let description = "删除指定日程（撤销专用，模型不可直接调用）"
    let permission: AgentToolPermission = .destructive
    var visibleToModel: Bool { false }

    let parametersSchema = AgentToolParametersSchema(
        properties: ["event_id": AgentToolProperty(type: "string", description: "要删除的日程UUID", enumValues: nil, items: nil)],
        required: ["event_id"]
    )

    let calendarManager: CalendarManager
    init(calendarManager: CalendarManager) { self.calendarManager = calendarManager }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let idStr = parameters["event_id"] as? String, let id = UUID(uuidString: idStr) else {
            throw AgentToolError.missingParameter("event_id")
        }
        calendarManager.deleteEvent(id: id)
        return AgentToolResult(success: true, message: "已删除日程", data: nil, undoAction: nil)
    }
}
