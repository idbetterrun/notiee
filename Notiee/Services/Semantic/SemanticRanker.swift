import Foundation

/// 关键词保底 + 语义阈值的混合排序。纯逻辑、可确定性单测。
struct SemanticRanker {
    let threshold: Float

    init(threshold: Float = 0.45) {
        self.threshold = threshold
    }

    func rank(
        queryVector: [Float]?,
        queryText: String,
        candidates: [(record: NoteRecord, vector: [Float]?)],
        limit: Int
    ) -> [NoteRecord] {
        let q = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        struct Scored { let record: NoteRecord; let score: Float }
        var scored: [Scored] = []

        for c in candidates {
            let keywordHit = matchesKeyword(c.record, query: q)
            let sim: Float = {
                guard let qv = queryVector, let v = c.vector else { return 0 }
                return VectorMath.cosineSimilarity(qv, v)
            }()

            if keywordHit {
                scored.append(Scored(record: c.record, score: sim + 1.0))
            } else if queryVector != nil, sim >= threshold {
                scored.append(Scored(record: c.record, score: sim))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.record }
    }

    private func matchesKeyword(_ r: NoteRecord, query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return r.title.localizedCaseInsensitiveContains(query)
            || r.summary.localizedCaseInsensitiveContains(query)
            || r.ocrText.localizedCaseInsensitiveContains(query)
    }
}
