import Foundation

/// 中心化的 Spark 档位限额出口。**全 App 唯一按档位分叉之处**：
/// Notiee+（BYOK）恒为「不限」；Notiee（免费）读 `CurrentEntitlement.tier`
/// （Phase 4 前恒 `.free`）。所有 Spark 限额调用方只读这里，不各自判断。
enum SparkTierLimits {

    // MARK: - 档位能力

    #if NOTIEE_PLUS
    static var maxSessionRounds: Int? { nil }        // nil = 不限
    static var maxMemoryEntries: Int? { nil }
    static var isAgentAllowed: Bool { true }
    static func isTextModelAllowed(_ id: String) -> Bool { true }
    #else
    private static var isPro: Bool { CurrentEntitlement.tier == .pro }
    static var maxSessionRounds: Int? { isPro ? nil : 20 }
    static var maxMemoryEntries: Int? { isPro ? nil : 5 }
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

    /// 给定已存记忆条数与本次待写入新条数，返回**允许写入的新条数**。
    static func acceptedNewMemoryCount(existingCount: Int, incoming: Int) -> Int {
        guard let cap = maxMemoryEntries else { return incoming }
        return Swift.max(0, Swift.min(incoming, cap - existingCount))
    }
}
