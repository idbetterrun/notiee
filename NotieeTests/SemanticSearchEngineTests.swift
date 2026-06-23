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
