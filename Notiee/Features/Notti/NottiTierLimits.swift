import Foundation

/// 中心化的 Notti 档位限额出口。**全 App 唯一按档位分叉之处**：
/// Notiee+（BYOK）恒为「不限」；Notiee（免费）读 `CurrentEntitlement.tier`
/// （Phase 4 前恒 `.free`）。所有 Notti 限额调用方只读这里，不各自判断。
enum NottiTierLimits {

    // MARK: - 档位能力

    #if NOTIEE_PLUS
    static var maxSessionRounds: Int? { nil }        // nil = 不限
    static var maxMemoryRecallCount: Int { 10 }
    static var isAgentAllowed: Bool { true }
    static func isTextModelAllowed(_ id: String) -> Bool { true }
    #else
    private static var isPro: Bool { CurrentEntitlement.tier == .pro }
    static var maxSessionRounds: Int? { isPro ? nil : 20 }
    static var maxMemoryRecallCount: Int { isPro ? 10 : 5 }
    static var isAgentAllowed: Bool { isPro }
    static func isTextModelAllowed(_ id: String) -> Bool {
        guard let model = CuratedModelCatalog.model(id: id), model.kind == .text else { return false }
        return CuratedModelCatalog.isAllowed(model, for: CurrentEntitlement.tier)
    }
    #endif

    // MARK: - 纯函数（供强制点调用 + 单测）

    static func sessionRoundLimitReached(currentRounds: Int) -> Bool {
        guard let max = maxSessionRounds else { return false }
        return currentRounds >= max
    }

    /// 本地记忆不设条数上限；保留纯函数接口以兼容旧调用方。
    static func acceptedNewMemoryCount(existingCount: Int, incoming: Int) -> Int {
        Swift.max(0, incoming)
    }
}
