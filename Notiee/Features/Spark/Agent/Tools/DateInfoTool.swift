import Foundation

@MainActor
final class DateInfoTool: AgentTool {
    let name = "date_info"
    let description = "查询某个日期是星期几、对应的标准日期(yyyy-MM-dd)、以及距今天的天数。凡涉及'某天星期几'或相对日期换算，必须调用本工具，不要自行心算。"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "date": AgentToolProperty(type: "string",
                description: "日期，可为 today/tomorrow、yyyy-MM-dd、ISO8601，或中文相对表达如 今天/明天/后天/下周三",
                enumValues: nil, items: nil)
        ],
        required: ["date"]
    )

    private let now: () -> Date
    private let calendar: Calendar

    init(now: @escaping () -> Date = { Date() }, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.now = now
        self.calendar = calendar
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let raw = parameters["date"] as? String, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AgentToolError.missingParameter("date")
        }
        guard let date = resolve(raw) else {
            return AgentToolResult(success: false,
                message: "无法解析日期「\(raw)」，请给出明确日期（如 2026-06-24）。",
                data: nil, undoAction: nil)
        }
        let today = calendar.startOfDay(for: now())
        let target = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        let iso = isoString(target)
        let weekday = weekdayName(target)
        let rel: String
        switch offset {
        case 0: rel = "就是今天"
        case 1: rel = "1 天后"
        case -1: rel = "1 天前"
        case let d where d > 0: rel = "\(d) 天后"
        default: rel = "\(-offset) 天前"
        }
        return AgentToolResult(success: true,
            message: "\(iso) 是\(weekday)，\(rel)。",
            data: ["iso": iso, "weekday": weekday, "offset_days": offset],
            undoAction: nil)
    }

    private func resolve(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let todayStart = calendar.startOfDay(for: now())
        switch s {
        case "today", "今天": return todayStart
        case "tomorrow", "明天": return calendar.date(byAdding: .day, value: 1, to: todayStart)
        case "后天": return calendar.date(byAdding: .day, value: 2, to: todayStart)
        case "yesterday", "昨天": return calendar.date(byAdding: .day, value: -1, to: todayStart)
        default:
            return CalendarQueryTool.parseDate(raw)
        }
    }

    private func isoString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func weekdayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale.current
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
