import Foundation

/// 选择策略 + 降级链：云端（开关开 && 配置全）→ 本地。
final class HybridEmbeddingService: EmbeddingService {
    private let local: EmbeddingService
    private let cloud: EmbeddingService?
    private let preferCloud: @Sendable () -> Bool

    init(local: EmbeddingService, cloud: EmbeddingService?, preferCloud: @escaping @Sendable () -> Bool) {
        self.local = local
        self.cloud = cloud
        self.preferCloud = preferCloud
    }

    var modelIdentifier: String {
        (preferCloud() ? cloud?.modelIdentifier : nil) ?? local.modelIdentifier
    }

    func embed(_ text: String) async throws -> [Float] {
        if preferCloud(), let cloud {
            if let v = try? await cloud.embed(text) { return v }
        }
        return try await local.embed(text)
    }

    func embedTagged(_ text: String) async throws -> EmbeddingResult {
        if preferCloud(), let cloud {
            if let v = try? await cloud.embed(text) {
                return EmbeddingResult(vector: v, model: cloud.modelIdentifier)
            }
        }
        let v = try await local.embed(text)
        return EmbeddingResult(vector: v, model: local.modelIdentifier)
    }
}
