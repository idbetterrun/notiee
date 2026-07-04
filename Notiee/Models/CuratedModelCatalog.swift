import Foundation

enum ModelTier: String, Sendable {
    case free
    case pro
}

enum CuratedModelKind: String, Sendable {
    case text
    case vision
}

struct CuratedModel: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let kind: CuratedModelKind
    let tier: ModelTier
}

enum CuratedModelCatalog {
    static let all: [CuratedModel] = [
        CuratedModel(id: "deepseek-v4-flash",      displayName: "DeepSeek v4-flash",      kind: .text,   tier: .free),
        CuratedModel(id: "MiniMax-M3",             displayName: "MiniMax M3",             kind: .text,   tier: .pro),
        CuratedModel(id: "MiniMax-M2.7-highspeed", displayName: "MiniMax M2.7-highspeed", kind: .text,   tier: .pro),
        CuratedModel(id: "MiniMax-M2.7",           displayName: "MiniMax M2.7",           kind: .text,   tier: .pro),
        CuratedModel(id: "deepseek-v4-pro",        displayName: "DeepSeek v4-pro",        kind: .text,   tier: .pro),
        CuratedModel(id: "doubao-seed-2-0-mini",   displayName: "Doubao-Seed-2.0-mini",   kind: .vision, tier: .free),
        CuratedModel(id: "doubao-seed-2-0-lite",   displayName: "Doubao-Seed-2.0-lite",   kind: .vision, tier: .pro),
        CuratedModel(id: "doubao-seed-2-1-pro",    displayName: "Doubao-Seed-2.1-Pro",    kind: .vision, tier: .pro),
    ]

    static func models(kind: CuratedModelKind) -> [CuratedModel] {
        all.filter { $0.kind == kind }
    }

    static func model(id: String) -> CuratedModel? {
        all.first { $0.id == id }
    }

    static func isAllowed(_ model: CuratedModel, for tier: ModelTier) -> Bool {
        tier == .pro ? true : model.tier == .free
    }

    static func defaultModel(kind: CuratedModelKind, for tier: ModelTier) -> CuratedModel {
        models(kind: kind).first { $0.tier == .free } ?? models(kind: kind)[0]
    }
}

struct CuratedModelSelection {
    let defaults: UserDefaults
    static let live = CuratedModelSelection(defaults: .standard)

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func textModelID(for tier: ModelTier) -> String {
        resolved(stored: defaults.string(forKey: UDK.selectedTextModel), kind: .text, tier: tier)
    }

    func visionModelID(for tier: ModelTier) -> String {
        resolved(stored: defaults.string(forKey: UDK.selectedVisionModel), kind: .vision, tier: tier)
    }

    func setTextModel(_ id: String) { defaults.set(id, forKey: UDK.selectedTextModel) }
    func setVisionModel(_ id: String) { defaults.set(id, forKey: UDK.selectedVisionModel) }

    private func resolved(stored: String?, kind: CuratedModelKind, tier: ModelTier) -> String {
        if let stored,
           let model = CuratedModelCatalog.model(id: stored),
           model.kind == kind,
           CuratedModelCatalog.isAllowed(model, for: tier) {
            return stored
        }
        return CuratedModelCatalog.defaultModel(kind: kind, for: tier).id
    }
}

/// 当前档位。**门控总闸**：Phase 4 起由后端真值驱动（`EntitlementStore` 写入），
/// 持久化到 UserDefaults 以便跨启动即时、且可从非主线程同步读取。默认 `.free`。
/// 客户端档位仅解锁 UI；后端对每次 AI 调用二次校验，改这里骗不到额度。
enum CurrentEntitlement {
    /// 可注入（测试用）；生产恒为 `.standard`。
    static var defaults: UserDefaults = .standard

    static var tier: ModelTier {
        get { ModelTier(rawValue: defaults.string(forKey: UDK.entitlementTier) ?? "") ?? .free }
        set { defaults.set(newValue.rawValue, forKey: UDK.entitlementTier) }
    }
}
