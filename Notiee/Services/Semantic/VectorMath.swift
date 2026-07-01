import Foundation

enum VectorMath {
    /// 余弦相似度。长度不一致或空向量返回 0（视为不相关）。
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}
