import Foundation

@MainActor
final class CalendarQueryTool: AgentTool {
    let name = "calendar_query"
    let description = "查询用户的日程安排，支持按时间范围和关键词筛选"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "time_range": AgentToolProperty(type: "string", description: "时间范围", enumValues: ["today", "this_week", "this_month", "custom"], items: nil),
            "start_date": AgentToolProperty(type: "string", description: "起始日期 ISO8601（time_range=custom时必填）", enumValues: nil, items: nil),
            "end_date": AgentToolProperty(type: "string", description: "结束日期 ISO8601（time_range=custom时必填）", enumValues: nil, items: nil),
            "keyword": AgentToolProperty(type: "string", description: "事件标题关键词（可选）", enumValues: nil, items: nil)
        ],
        required: []
    )

    let calendarManager: CalendarManager

    init(calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        let now = Date()
        let calendar = Calendar.current
        let range = parameters["time_range"] as? String ?? "today"
        let keyword = parameters["keyword"] as? String

        let start: Date
        let end: Date
        switch range {
        case "today":
            start = calendar.startOfDay(for: now)
            end = calendar.date(byAdding: .day, value: 1, to: start)!
        case "this_week":
            start = calendar.startOfDay(for: now)
            end = calendar.date(byAdding: .day, value: 7, to: start)!
        case "this_month":
            start = calendar.startOfDay(for: now)
            end = calendar.date(byAdding: .month, value: 1, to: start)!
        case "custom":
            if let s = (parameters["start_date"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) }),
               let e = (parameters["end_date"] as? String).flatMap({ ISO8601DateFormatter().date(from: $0) }) {
                start = s; end = e
            } else {
                throw AgentToolError.missingParameter("start_date/end_date")
            }
        default:
            start = calendar.startOfDay(for: now)
            end = calendar.date(byAdding: .day, value: 1, to: start)!
        }

        var events = calendarManager.allEvents.filter { $0.startDate >= start && $0.startDate < end }
        if let kw = keyword { events = events.filter { $0.title.localizedCaseInsensitiveContains(kw) } }

        let eventsData = events.map { event -> [String: Any] in
            ["id": event.id.uuidString, "title": event.title, "start": event.startDate.ISO8601Format(),
             "end": event.endDate.ISO8601Format(), "all_day": event.isAllDay]
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none

        let message = events.isEmpty
            ? "从 \(dateFormatter.string(from: start)) 到 \(dateFormatter.string(from: end)) 没有日程。"
            : "找到 \(events.count) 条日程：\n" + events.enumerated().map {
                "  [\($0+1)] \($1.title) - \($1.startDate.formatted(date: .abbreviated, time: .shortened))"
            }.joined(separator: "\n")

        return AgentToolResult(success: true, message: message, data: ["events": eventsData], undoAction: nil)
    }
}
