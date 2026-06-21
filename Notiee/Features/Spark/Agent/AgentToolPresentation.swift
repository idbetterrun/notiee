import Foundation

struct AgentToolPresentation {
    let icon: String        // SF Symbol
    let displayName: String
    let runningText: String // 进行时文案

    static func forName(_ name: String) -> AgentToolPresentation {
        switch name {
        case "note_search":
            return .init(icon: "magnifyingglass", displayName: "搜索拍记", runningText: "正在搜索拍记…")
        case "note_get_detail":
            return .init(icon: "doc.text", displayName: "查看拍记", runningText: "正在查看拍记…")
        case "note_create":
            return .init(icon: "square.and.pencil", displayName: "创建拍记", runningText: "正在创建拍记…")
        case "note_update":
            return .init(icon: "pencil", displayName: "修改拍记", runningText: "正在修改拍记…")
        case "todo_list":
            return .init(icon: "checklist", displayName: "查看待办", runningText: "正在查看待办…")
        case "todo_create":
            return .init(icon: "plus.circle", displayName: "创建待办", runningText: "正在创建待办…")
        case "todo_complete":
            return .init(icon: "checkmark.circle", displayName: "完成待办", runningText: "正在更新待办…")
        case "calendar_query":
            return .init(icon: "calendar", displayName: "查询日程", runningText: "正在查询日程…")
        case "schedule_create":
            return .init(icon: "calendar.badge.plus", displayName: "创建日程", runningText: "正在创建日程…")
        case "schedule_update":
            return .init(icon: "calendar.badge.clock", displayName: "修改日程", runningText: "正在修改日程…")
        case "memory_get":
            return .init(icon: "brain", displayName: "查看记忆", runningText: "正在查看记忆…")
        default:
            return .init(icon: "wrench.and.screwdriver", displayName: name, runningText: "正在执行…")
        }
    }
}
