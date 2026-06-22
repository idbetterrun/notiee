import Foundation

@MainActor
final class ScheduleCreateTool: AgentTool {
    let name = "schedule_create"
    let description = "创建一条新的日程/事件。用于用户要求安排、预约、记录某个时间点的活动。"
    let permission: AgentToolPermission = .write

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "title": AgentToolProperty(type: "string", description: "日程标题", enumValues: nil, items: nil),
            "start_date": AgentToolProperty(type: "string", description: "开始时间 ISO8601 或 yyyy-MM-dd", enumValues: nil, items: nil),
            "end_date": AgentToolProperty(type: "string", description: "结束时间（可选，默认开始后 1 小时）", enumValues: nil, items: nil),
            "all_day": AgentToolProperty(type: "string", description: "是否全天，传 true/false（可选）", enumValues: ["true", "false"], items: nil)
        ],
        required: ["title", "start_date"]
    )

    let calendarManager: CalendarManager

    init(calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let title = parameters["title"] as? String, !title.isEmpty else {
            throw AgentToolError.missingParameter("title")
        }
        guard let start = CalendarQueryTool.parseDate(parameters["start_date"] as? String) else {
            throw AgentToolError.missingParameter("start_date")
        }
        let end = CalendarQueryTool.parseDate(parameters["end_date"] as? String)
            ?? start.addingTimeInterval(3600)
        let allDay = (parameters["all_day"] as? String) == "true"

        let event = ScheduledEvent(
            title: title,
            startDate: start,
            endDate: end,
            kind: .uncategorized,
            source: .ai,
            isAllDay: allDay
        )
        calendarManager.addEvent(event)

        let when = start.formatted(date: .abbreviated, time: allDay ? .omitted : .shortened)
        return AgentToolResult(
            success: true,
            message: "已创建日程「\(title)」（\(when)）",
            data: ["event_id": event.id.uuidString],
            undoAction: AgentUndoAction(
                toolName: "schedule_delete",
                description: "删除刚创建的日程「\(title)」",
                undoParameters: ["event_id": event.id.uuidString],
                snapshotPath: nil
            )
        )
    }
}
