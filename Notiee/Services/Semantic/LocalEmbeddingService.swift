import Foundation
import NaturalLanguage

/// 端上句向量。优先简体中文，回退英文；都不可用则抛 .unavailable（上层降级到关键词）。
final class LocalEmbeddingService: EmbeddingService {
    let modelIdentifier = "nlembedding-sentence-v1"

    func embed(_ text: String) async throws -> [Float] {
        let embedding = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
        guard let embedding else { throw EmbeddingError.unavailable }
        guard let vec = embedding.vector(for: text) else { throw EmbeddingError.cannotEmbed }
        return vec.map { Float($0) }
    }
}
