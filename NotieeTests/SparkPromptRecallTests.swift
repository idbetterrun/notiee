import XCTest
@testable import Notiee

@MainActor
final class SparkPromptRecallTests: XCTestCase {
    private func makeService() -> SparkAIService {
        SparkAIService()
    }
    private func rec(_ title: String, summary: String, body: String) -> NoteRecord {
        var r = NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
        r.summary = summary
        r.detailedContent = body
        return r
    }

    func testPrompt_rendersAnchorAndSemanticLayers_withContinuousNumbering() {
        let anchor = rec("锚点笔记", summary: "锚点摘要", body: "锚点正文不该整段进 prompt")
        let semantic = rec("语义老笔记", summary: "语义摘要", body: "语义层应注入的全文内容ABC")
        let recall = RecalledRecords(records: [anchor, semantic], semanticStartIndex: 1)

        let p = makeService().buildSystemPrompt(recall: recall, recentRounds: [], upcomingEvents: [])

        XCTAssertTrue(p.contains("[记录1]"), "锚点编号")
        XCTAssertTrue(p.contains("[记录2]"), "语义编号连续")
        XCTAssertTrue(p.contains("语义摘要") || p.contains("语义层应注入的全文内容ABC"), "语义记录可见")
        XCTAssertTrue(p.contains("语义层应注入的全文内容ABC"), "语义层注入全文正文")
        XCTAssertTrue(p.contains("共 2 条"), "记录总数=合并后条数")
    }

    func testPrompt_emptyRecall_noRecordBlockCrash() {
        let p = makeService().buildSystemPrompt(recall: .empty, recentRounds: [], upcomingEvents: [])
        XCTAssertTrue(p.contains("共 0 条"))
    }

    func testPinnedFullText_injectsDetailedContent() {
        let r = rec("英文文章", summary: "摘要很短", body: """
        This is a full article with multiple paragraphs. It contains detailed content
        that would normally be truncated or not sent at all. The user wants to translate this.
        """)
        let block = SparkAIService.buildPinnedFullTextBlock(pinnedIDs: [r.id], from: [r])
        XCTAssertTrue(block.contains("完整内容"))
        XCTAssertTrue(block.contains("full article with multiple paragraphs"))
    }

    func testPinnedFullText_emptyIDs_returnsEmpty() {
        let r = rec("x", summary: "s", body: "b")
        let block = SparkAIService.buildPinnedFullTextBlock(pinnedIDs: [], from: [r])
        XCTAssertEqual(block, "")
    }

    func testPinnedFullText_recordNotFound_returnsEmpty() {
        let r = rec("x", summary: "s", body: "b")
        let otherID = UUID()
        let block = SparkAIService.buildPinnedFullTextBlock(pinnedIDs: [otherID], from: [r])
        XCTAssertEqual(block, "")
    }

    func testPinnedFullText_multipleRecords() {
        let r1 = rec("文章A", summary: "s1", body: "内容A")
        let r2 = rec("文章B", summary: "s2", body: "内容B")
        let block = SparkAIService.buildPinnedFullTextBlock(pinnedIDs: [r1.id, r2.id], from: [r1, r2])
        XCTAssertTrue(block.contains("拍记 1"))
        XCTAssertTrue(block.contains("拍记 2"))
        XCTAssertTrue(block.contains("内容A"))
        XCTAssertTrue(block.contains("内容B"))
    }

    func testPinnedFullText_emptyBodySkipped() {
        let r = rec("无正文", summary: "s", body: "")
        let block = SparkAIService.buildPinnedFullTextBlock(pinnedIDs: [r.id], from: [r])
        XCTAssertEqual(block, "")
    }
}
