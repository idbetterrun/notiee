import Foundation

/// 本地启发式：判断用户消息是否像「让 Spark 干活」的写/执行请求，
/// 用于在非 Agent 模式下提示切换 Agent。宁可漏判，不要误判问答。
enum SparkIntentDetector {
    private static let actionPatterns: [String] = [
        // 中文动作动词
        "帮我创建", "帮我加", "帮我记", "帮我安排", "帮我预约", "帮我提醒",
        "创建一个", "新建一个", "加一个", "记一条", "记一下", "提醒我", "安排一下", "预约",
        "添加待办", "新建日程", "创建日程", "建个", "排个",
        // 英文动作动词（词边界，避免误伤）
        "\\bcreate\\b", "\\badd\\b", "\\bremind\\b", "\\bschedule\\b",
        "\\bset (a |an )?(reminder|todo|event)\\b", "\\bmake (a |an )?(note|todo|event)\\b",
        "\\bnew (note|todo|event|schedule)\\b",
    ]

    static func looksLikeActionRequest(_ message: String) -> Bool {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return actionPatterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}
