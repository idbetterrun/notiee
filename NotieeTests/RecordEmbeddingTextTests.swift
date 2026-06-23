import XCTest
@testable import Notiee

final class RecordEmbeddingTextTests: XCTestCase {
    private func record(title: String, summary: String, ocr: String) -> NoteRecord {
        var r = NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
        r.summary = summary
        r.ocrText = ocr
        return r
    }

    func testCompose_joinsTitleSummaryOcr() {
        let text = RecordEmbeddingText.compose(record(title: "机器学习", summary: "梯度下降", ocr: "loss"))
        XCTAssertTrue(text.contains("机器学习"))
        XCTAssertTrue(text.contains("梯度下降"))
        XCTAssertTrue(text.contains("loss"))
    }

    func testCompose_truncatesToMaxLength() {
        let long = String(repeating: "字", count: 5000)
        let text = RecordEmbeddingText.compose(record(title: long, summary: "", ocr: ""))
        XCTAssertLessThanOrEqual(text.count, RecordEmbeddingText.maxLength)
    }

    func testContentHash_isStableAndSensitive() {
        XCTAssertEqual(RecordEmbeddingText.contentHash("abc"), RecordEmbeddingText.contentHash("abc"))
        XCTAssertNotEqual(RecordEmbeddingText.contentHash("abc"), RecordEmbeddingText.contentHash("abd"))
    }
}
