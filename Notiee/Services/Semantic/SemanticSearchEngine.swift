import Foundation

/// 协调：为候选拍记懒补算/复用向量 → 调用 SemanticRanker 排序。
@MainActor
final class SemanticSearchEngine {
    private let embeddingService: EmbeddingService
    private let index: EmbeddingIndex
    private let ranker: SemanticRanker

    init(embeddingService: EmbeddingService, index: EmbeddingIndex, threshold: Float = 0.45) {
        self.embeddingService = embeddingService
        self.index = index
        self.ranker = SemanticRanker(threshold: threshold)
    }

    func search(query: String, in records: [NoteRecord], limit: Int) async -> [NoteRecord] {
        let queryVector = try? await embeddingService.embed(query)

        var candidates: [(record: NoteRecord, vector: [Float]?)] = []
        for record in records {
            let vector = await ensureVector(for: record)
            candidates.append((record, vector))
        }

        return ranker.rank(queryVector: queryVector, queryText: query, candidates: candidates, limit: limit)
    }

    /// 后台回填（启动时可调用）。失败的单条跳过，不影响整体。
    func backfill(records: [NoteRecord]) async {
        for record in records { _ = await ensureVector(for: record) }
    }

    private func ensureVector(for record: NoteRecord) async -> [Float]? {
        let text = RecordEmbeddingText.compose(record)
        guard !text.isEmpty else { return nil }
        let hash = RecordEmbeddingText.contentHash(text)

        if let existing = index.entry(for: record.id),
           existing.contentHash == hash,
           existing.model == embeddingService.modelIdentifier {
            return existing.vector
        }

        guard let vector = try? await embeddingService.embed(text) else { return nil }
        index.set(EmbeddingEntry(vector: vector, model: embeddingService.modelIdentifier, contentHash: hash), for: record.id)
        return vector
    }
}
