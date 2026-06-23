import Foundation

enum TodoDueBucket: Int, CaseIterable {
    case overdue, today, tomorrow, thisWeek, later, noDueDate

    var title: String {
        switch self {
        case .overdue: return "已逾期"
        case .today: return "今天"
        case .tomorrow: return "明天"
        case .thisWeek: return "本周"
        case .later: return "更晚"
        case .noDueDate: return "无截止日期"
        }
    }
}

enum TodoBucketer {
    static func bucket(for todo: NoteTodo, now: Date = Date(), calendar: Calendar = .current) -> TodoDueBucket {
        guard let due = todo.dueDate else { return .noDueDate }
        let startToday = calendar.startOfDay(for: now)
        let startDue = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: startToday, to: startDue).day ?? 0
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        if days == 1 { return .tomorrow }
        if days <= 7 { return .thisWeek }
        return .later
    }

    /// Today 概览：逾期 / 今天 / 无截止 视为「当下可执行」。
    static func isActionableNow(_ todo: NoteTodo, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch bucket(for: todo, now: now, calendar: calendar) {
        case .overdue, .today, .noDueDate: return true
        case .tomorrow, .thisWeek, .later: return false
        }
    }
}
