import XCTest
@testable import Notiee

final class SemanticRankerTests: XCTestCase {
    private func rec(_ title: String) -> NoteRecord {
        NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
    }

    func testSemanticMatch_includedAboveThreshold_evenWithoutKeyword() {
        let ranker = SemanticRanker(threshold: 0.5)
        let r = rec("深度学习")
        let out = ranker.rank(
            queryVector: [1, 0], queryText: "机器学习",
            candidates: [(r, [0.9, 0.1])],
            limit: 5
        )
        XCTAssertEqual(out.map { $0.id }, [r.id])
    }

    func testBelowThreshold_excluded() {
        let ranker = SemanticRanker(threshold: 0.8)
        let r = rec("量子计算")
        let out = ranker.rank(
            queryVector: [1, 0], queryText: "机器学习",
            candidates: [(r, [0, 1])],
            limit: 5
        )
        XCTAssertTrue(out.isEmpty)
    }

    func testKeywordHit_alwaysIncludedAndRankedFirst() {
        let ranker = SemanticRanker(threshold: 0.8)
        let kw = rec("机器学习导论")
        let sem = rec("深度学习")
        let out = ranker.rank(
            queryVector: [1, 0], queryText: "机器学习",
            candidates: [(sem, [0.95, 0.05]), (kw, [0, 1])],
            limit: 5
        )
        XCTAssertEqual(out.first?.id, kw.id, "关键词命中应排在最前")
        XCTAssertTrue(out.contains { $0.id == kw.id })
    }

    func testNilQueryVector_fallsBackToKeywordOnly() {
        let ranker = SemanticRanker(threshold: 0.5)
        let kw = rec("机器学习")
        let other = rec("烹饪")
        let out = ranker.rank(
            queryVector: nil, queryText: "机器学习",
            candidates: [(kw, nil), (other, nil)],
            limit: 5
        )
        XCTAssertEqual(out.map { $0.id }, [kw.id])
    }

    func testRespectsLimit() {
        let ranker = SemanticRanker(threshold: 0.0)
        let cands = (0..<10).map { (rec("机器学习\($0)"), [Float(1), 0]) }
        let out = ranker.rank(queryVector: [1, 0], queryText: "机器学习", candidates: cands, limit: 3)
        XCTAssertEqual(out.count, 3)
    }
}
