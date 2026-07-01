import XCTest
@testable import Notiee

/// 把指定文本映射到指定向量；其余返回零向量。
private final class StubEmbeddingService: EmbeddingService {
    let modelIdentifier = "stub-v1"
    let table: [String: [Float]]
    init(_ table: [String: [Float]]) { self.table = table }
    func embed(_ text: String) async throws -> [Float] {
        for (k, v) in table where text.contains(k) { return v }
        return [0, 0]
    }
}

@MainActor
final class SemanticSearchEngineTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("emb-\(UUID()).json")
    }
    private func rec(_ title: String) -> NoteRecord {
        NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
    }

    func testSemanticSearch_findsNonKeywordMatch() async {
        let stub = StubEmbeddingService(["机器学习": [1, 0], "深度学习": [0.95, 0.05]])
        let engine = SemanticSearchEngine(
            embeddingService: stub, index: EmbeddingIndex(fileURL: tmpURL()), threshold: 0.5
        )
        let r = rec("深度学习")
        let out = await engine.search(query: "机器学习", in: [r], limit: 5)
        XCTAssertEqual(out.map { $0.id }, [r.id])
    }

    func testEmbeddingCached_secondSearchReusesIndex() async {
        let index = EmbeddingIndex(fileURL: tmpURL())
        let stub = StubEmbeddingService(["机器学习": [1, 0], "深度学习": [0.9, 0.1]])
        let engine = SemanticSearchEngine(embeddingService: stub, index: index, threshold: 0.5)
        let r = rec("深度学习")
        _ = await engine.search(query: "机器学习", in: [r], limit: 5)
        XCTAssertNotNil(index.entry(for: r.id), "首次搜索后应缓存向量")
    }

    // MARK: - related(to:) 记录到记录的语义联想

    func testRelated_excludesSelfAndBelowThreshold() async {
        let stub = StubEmbeddingService(["源": [1, 0], "强": [1, 0], "中": [0.6, 0.8], "弱": [0, 1]])
        let engine = SemanticSearchEngine(embeddingService: stub, index: EmbeddingIndex(fileURL: tmpURL()))
        let source = rec("源")
        let strong = rec("强") // cosine 1.0
        let mid = rec("中")    // cosine 0.6
        let weak = rec("弱")   // cosine 0.0
        let out = await engine.related(to: source, in: [source, strong, mid, weak], limit: 5, threshold: 0.7)
        XCTAssertEqual(out.map { $0.id }, [strong.id], "排除自身、过滤低于阈值（中=0.6、弱=0）")
    }

    func testRelated_respectsLimitAndOrdersByScore() async {
        let stub = StubEmbeddingService(["源": [1, 0], "强": [1, 0], "中": [0.6, 0.8]])
        let engine = SemanticSearchEngine(embeddingService: stub, index: EmbeddingIndex(fileURL: tmpURL()))
        let source = rec("源")
        let strong = rec("强")
        let mid = rec("中")
        let out = await engine.related(to: source, in: [mid, strong], limit: 1, threshold: 0.5)
        XCTAssertEqual(out.map { $0.id }, [strong.id], "按分数降序并受 limit 截断")
    }

    func testRelated_emptyWhenSourceHasNoEmbeddableText() async {
        let stub = StubEmbeddingService(["x": [1, 0]])
        let engine = SemanticSearchEngine(embeddingService: stub, index: EmbeddingIndex(fileURL: tmpURL()))
        let source = NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: [], title: "")
        let other = rec("x")
        let out = await engine.related(to: source, in: [other], limit: 5, threshold: 0.5)
        XCTAssertTrue(out.isEmpty, "源记录无可嵌入文本时返回空")
    }

    func testEmbeddingFailure_fallsBackToKeyword() async {
        final class FailingService: EmbeddingService {
            let modelIdentifier = "fail"
            func embed(_ text: String) async throws -> [Float] { throw EmbeddingError.unavailable }
        }
        let engine = SemanticSearchEngine(
            embeddingService: FailingService(), index: EmbeddingIndex(fileURL: tmpURL()), threshold: 0.5
        )
        let kw = rec("机器学习")
        let other = rec("烹饪")
        let out = await engine.search(query: "机器学习", in: [kw, other], limit: 5)
        XCTAssertEqual(out.map { $0.id }, [kw.id], "向量不可用时退化为关键词")
    }
}
