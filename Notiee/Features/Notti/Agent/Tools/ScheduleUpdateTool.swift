import Foundation

@MainActor
final class ScheduleUpdateTool: AgentTool {
    let name = "schedule_update"
    let description = "修改一个已有日程的标题或时间。仅支持 Notiee/AI 创建的日程；系统日历事件需到系统「日历」App 修改。"
    let permission: AgentToolPermission = .write

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "event_id": AgentToolProperty(type: "string", description: "要修改的日程 UUID", enumValues: nil, items: nil),
            "title": AgentToolProperty(type: "string", description: "新标题（可选）", enumValues: nil, items: nil),
            "start_date": AgentToolProperty(type: "string", description: "新开始时间 ISO8601 或 yyyy-MM-dd（可选）", enumValues: nil, items: nil),
            "end_date": AgentToolProperty(type: "string", description: "新结束时间（可选）", enumValues: nil, items: nil)
        ],
        required: ["event_id"]
    )

    let calendarManager: CalendarManager

    init(calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let idStr = parameters["event_id"] as? String, let id = UUID(uuidString: idStr) else {
            throw AgentToolError.missingParameter("event_id")
        }

        guard let event = calendarManager.allEvents.first(where: { $0.id == id }) else {
            return AgentToolResult(success: false, message: "未找到该日程。", data: nil, undoAction: nil)
        }

        if case .systemCalendar = event.source {
            return AgentToolResult(
                success: false,
                message: "「\(event.title)」是系统日历事件，请到系统「日历」App 修改。",
                data: nil,
                undoAction: nil
            )
        }

        let oldTitle = event.title
        let oldStart = event.startDate
        let oldEnd = event.endDate

        let title = parameters["title"] as? String
        let start = CalendarQueryTool.parseDate(parameters["start_date"] as? String)
        let end = CalendarQueryTool.parseDate(parameters["end_date"] as? String)

        let ok = calendarManager.updateEvent(id: id, title: title, startDate: start, endDate: end, notes: nil)
        guard ok else {
            return AgentToolResult(success: false, message: "修改失败：该日程不可编辑。", data: nil, undoAction: nil)
        }

        let undoParams: [String: Any] = [
            "event_id": idStr,
            "title": oldTitle,
            "start_date": oldStart.ISO8601Format(),
            "end_date": oldEnd.ISO8601Format()
        ]
        return AgentToolResult(
            success: true,
            message: "已修改日程「\(title ?? oldTitle)」",
            data: ["event_id": idStr],
            undoAction: AgentUndoAction(
                toolName: "schedule_update",
                description: "恢复日程「\(oldTitle)」",
                undoParameters: undoParams,
                snapshotPath: nil
            )
        )
    }
}
