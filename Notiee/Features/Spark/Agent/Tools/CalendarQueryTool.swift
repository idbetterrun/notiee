import Foundation

@MainActor
final class CalendarQueryTool: AgentTool {
    let name = "calendar_query"
    let description = "查询用户的日程安排，支持按时间范围和关键词筛选"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "time_range": AgentToolProperty(type: "string", description: "时间范围", enumValues: ["today", "tomorrow", "day_after_tomorrow", "this_week", "this_month", "custom"], items: nil),
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

    /// 解析时间范围。永不抛错：custom 缺参或无法识别时降级为今天。
    nonisolated static func resolveDateRange(timeRange: String?, startDate: String?, endDate: String?,
                                 now: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        func days(_ n: Int, from d: Date) -> Date { calendar.date(byAdding: .day, value: n, to: d)! }

        switch timeRange {
        case "today":
            return (today, days(1, from: today))
        case "tomorrow":
            let t = days(1, from: today)
            return (t, days(1, from: t))
        case "day_after_tomorrow":
            let t = days(2, from: today)
            return (t, days(1, from: t))
        case "this_week":
            return (today, days(7, from: today))
        case "this_month":
            return (today, calendar.date(byAdding: .month, value: 1, to: today)!)
        case "custom":
            if let s = parseDate(startDate), let e = parseDate(endDate) {
                return (s, e)
            }
            return (today, days(1, from: today))
        default:
            return (today, days(1, from: today))
        }
    }

    /// 宽松日期解析：先试 ISO8601，再依次试常见格式。
    nonisolated static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: raw) { return d }
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
        ]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            fmt.dateFormat = format
            if let d = fmt.date(from: raw) { return d }
        }
        return nil
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        let now = Date()
        let calendar = Calendar.current
        let keyword = parameters["keyword"] as? String
        let (start, end) = Self.resolveDateRange(
            timeRange: parameters["time_range"] as? String,
            startDate: parameters["start_date"] as? String,
            endDate: parameters["end_date"] as? String,
            now: now, calendar: calendar
        )

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
