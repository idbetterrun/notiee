import Foundation

/// 云端 embedding。复用 Notti 文本模型的 endpoint/key，将 chat 路径替换为 embeddings 路径。
final class CloudEmbeddingService: EmbeddingService {
    struct Config { let endpoint: String; let apiKey: String; let model: String }
    private let configProvider: @Sendable () -> Config?

    init(configProvider: @escaping @Sendable () -> Config?) {
        self.configProvider = configProvider
    }

    var modelIdentifier: String { "cloud-" + (configProvider()?.model ?? "unknown") }

    func embed(_ text: String) async throws -> [Float] {
        guard let cfg = configProvider(), !cfg.apiKey.isEmpty, !cfg.model.isEmpty else {
            throw EmbeddingError.notConfigured
        }
        return try await OpenAICaller.callEmbedding(
            endpoint: Self.embeddingsEndpoint(from: cfg.endpoint),
            model: cfg.model, apiKey: cfg.apiKey, input: text
        )
    }

    /// 把 chat completions 端点改写成 embeddings 端点。
    static func embeddingsEndpoint(from chatEndpoint: String) -> String {
        if chatEndpoint.contains("/chat/completions") {
            return chatEndpoint.replacingOccurrences(of: "/chat/completions", with: "/embeddings")
        }
        if chatEndpoint.contains("/completions") {
            return chatEndpoint.replacingOccurrences(of: "/completions", with: "/embeddings")
        }
        return chatEndpoint
    }
}
