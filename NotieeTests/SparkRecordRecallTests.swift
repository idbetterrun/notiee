import XCTest
@testable import Notiee

@MainActor
final class SparkRecordRecallTests: XCTestCase {
    private func rec(_ title: String) -> NoteRecord {
        NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
    }

    func testMerge_semanticExcludesAnchorDuplicates_andReportsBoundary() {
        let a1 = rec("锚点1"); let a2 = rec("锚点2")
        let s1 = rec("语义1")
        let out = SparkRecordRecall.merge(anchors: [a1, a2], semantic: [a1, s1], cap: 20)
        XCTAssertEqual(out.records.map { $0.id }, [a1.id, a2.id, s1.id], "锚点在前、去掉语义里的重复")
        XCTAssertEqual(out.semanticStartIndex, 2, "语义层从第 3 条(下标2)开始")
    }

    func testMerge_capTruncates_andClampsBoundary() {
        let anchors = (0..<3).map { rec("锚\($0)") }
        let semantic = (0..<10).map { rec("语\($0)") }
        let out = SparkRecordRecall.merge(anchors: anchors, semantic: semantic, cap: 5)
        XCTAssertEqual(out.records.count, 5, "截到 cap")
        XCTAssertEqual(out.semanticStartIndex, 3, "边界=锚点数")
        XCTAssertEqual(out.records.prefix(3).map { $0.id }, anchors.map { $0.id })
    }

    func testRecall_mergesAnchorsAndSemantic_excludesEncryptedFromCandidates() async {
        let now = Date()
        func recAt(_ title: String, _ ago: TimeInterval, encrypted: Bool = false) -> NoteRecord {
            var r = NoteRecord(id: UUID(), capturedAt: now.addingTimeInterval(-ago), localImagePaths: ["x"], title: title)
            r.isEncrypted = encrypted
            return r
        }
        let newest = recAt("最新", 10)
        let secret = recAt("加密", 20, encrypted: true)
        let old = recAt("很老的记录", 99999)
        let all = [newest, secret, old]

        let stub = StubSearch(result: [old])
        let recaller = SparkRecordRecall(engine: stub, anchorCount: 1, semanticLimit: 5, mergedCap: 20)
        let out = await recaller.recall(query: "老", from: all)

        XCTAssertEqual(out.records.map { $0.id }, [newest.id, old.id])
        XCTAssertEqual(out.semanticStartIndex, 1)
        XCTAssertFalse(stub.lastCandidates.contains { $0.id == secret.id }, "加密记录不进语义候选")
    }
}

private final class StubSearch: SemanticSearching {
    let result: [NoteRecord]
    private(set) var lastCandidates: [NoteRecord] = []
    init(result: [NoteRecord]) { self.result = result }
    func search(query: String, in records: [NoteRecord], limit: Int) async -> [NoteRecord] {
        lastCandidates = records
        return result
    }
}
