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
        for record in records where !record.isEncrypted {
            let vector = await ensureVector(for: record)
            candidates.append((record, vector))
        }

        return ranker.rank(queryVector: queryVector, queryText: query, candidates: candidates, limit: limit)
    }

    /// 记录到记录的语义联想：用目标记录自身的向量，按余弦相似度找最相关的其它记录。
    /// 与按 query 字符串搜索不同——不做关键词保底，纯语义；阈值更高，避免被动推荐塞入弱相关。
    func related(to record: NoteRecord, in records: [NoteRecord], limit: Int, threshold: Float) async -> [NoteRecord] {
        guard let sourceVector = await ensureVector(for: record) else { return [] }

        var scored: [(record: NoteRecord, score: Float)] = []
        for candidate in records where candidate.id != record.id && !candidate.isEncrypted {
            guard let vector = await ensureVector(for: candidate) else { continue }
            let sim = VectorMath.cosineSimilarity(sourceVector, vector)
            if sim >= threshold {
                scored.append((candidate, sim))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.record }
    }

    /// 后台回填（启动时可调用）。失败的单条跳过，不影响整体。
    func backfill(records: [NoteRecord]) async {
        for record in records where !record.isEncrypted { _ = await ensureVector(for: record) }
    }

    /// Spark 用的标准装配：本地 NLEmbedding + 可选云端（复用文本模型 key）+ 共享索引。
    static func liveForSpark(settingsStore: AppSettingsPersisting) -> SemanticSearchEngine {
        let embeddingModel = UserDefaults.standard.string(forKey: "spark.semanticSearch.embeddingModel") ?? "text-embedding-3-small"
        let cloud = CloudEmbeddingService(configProvider: {
            let cfg = settingsStore.loadConfiguration(for: .text)
            return CloudEmbeddingService.Config(endpoint: cfg.activeEndpoint, apiKey: cfg.apiKey, model: embeddingModel)
        })
        let hybrid = HybridEmbeddingService(
            local: LocalEmbeddingService(),
            cloud: cloud,
            preferCloud: { UserDefaults.standard.bool(forKey: "spark.semanticSearch.useCloud") }
        )
        return SemanticSearchEngine(embeddingService: hybrid, index: .live)
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

        guard let result = try? await embeddingService.embedTagged(text) else { return nil }
        index.set(EmbeddingEntry(vector: result.vector, model: result.model, contentHash: hash), for: record.id)
        return result.vector
    }
}
