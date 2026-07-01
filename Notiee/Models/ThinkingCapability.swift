import Foundation

struct ThinkingLevel: Identifiable, Equatable, Sendable {
    let id: String        // "off"/"minimal"/"low"/"medium"/"high"/"on"
    let displayName: String
}

struct ThinkingCapability: Sendable {
    let levels: [ThinkingLevel]
    private let injector: @Sendable (ThinkingLevel, inout [String: Any]) -> Void

    func apply(level: ThinkingLevel, to payload: inout [String: Any]) {
        injector(level, &payload)
    }

    static func forProvider(_ provider: AIProviderType) -> ThinkingCapability {
        switch provider {
        case .doubaoText, .custom, .minimax:
            let levels = [
                ThinkingLevel(id: "minimal", displayName: String(localized: "极简思考")),
                ThinkingLevel(id: "low", displayName: String(localized: "低强度思考")),
                ThinkingLevel(id: "medium", displayName: String(localized: "中强度思考")),
                ThinkingLevel(id: "high", displayName: String(localized: "高强度思考"))
            ]
            return ThinkingCapability(levels: levels) { level, payload in
                payload["reasoning_effort"] = level.id
            }
        case .qwenText:
            let levels = [
                ThinkingLevel(id: "off", displayName: String(localized: "关闭思考")),
                ThinkingLevel(id: "on", displayName: String(localized: "开启思考"))
            ]
            return ThinkingCapability(levels: levels) { level, payload in
                payload["enable_thinking"] = (level.id != "off")
            }
        case .deepseek:
            let levels = [
                ThinkingLevel(id: "off", displayName: String(localized: "关闭思考")),
                ThinkingLevel(id: "on", displayName: String(localized: "开启思考"))
            ]
            return ThinkingCapability(levels: levels) { level, payload in
                payload["reasoning_effort"] = (level.id == "off") ? "minimal" : "high"
            }
        case .qwenVision, .doubaoVision:
            return ThinkingCapability(levels: []) { _, _ in }
        }
    }
}
