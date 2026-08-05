import XCTest
@testable import Notiee

final class NewUIPreviewRecordPresentationTests: XCTestCase {
    func testOrganizedMarkdownSuppressesWhitespaceTrimmedDuplicateSummary() {
        let record = makeRecord(
            summary: "  相同内容\n",
            detailedContent: "相同内容"
        )

        let markdown = NewUIPreviewRecordPresentation.organizedMarkdown(for: record)

        XCTAssertEqual(markdown.components(separatedBy: "相同内容").count - 1, 1)
        XCTAssertTrue(markdown.contains("## "))
    }

    func testOrganizedMarkdownKeepsDistinctSummaryAndStructuredSections() {
        var record = makeRecord(summary: "简短导语", detailedContent: "完整正文")
        record.keyPoints = ["第一点", "第二点"]
        record.definitions = [KeyDefinition(term: "术语", explanation: "解释")]

        let markdown = NewUIPreviewRecordPresentation.organizedMarkdown(for: record)

        XCTAssertTrue(markdown.contains("\n\n简短导语"))
        XCTAssertTrue(markdown.contains("\n\n完整正文"))
        XCTAssertTrue(markdown.contains("- 第一点"))
        XCTAssertTrue(markdown.contains("**术语**"))
        XCTAssertTrue(markdown.contains("解释"))
    }

    func testVisibleTextOnlyUsesSelectedSectionContent() {
        let record = makeRecord(
            summary: "整理摘要",
            detailedContent: "整理正文",
            ocrText: "照片原文"
        )
        let todos = ["提交纪要", "回复邮件"]

        let organized = NewUIPreviewRecordPresentation.visibleText(
            for: .organized,
            record: record,
            todos: todos
        )
        let raw = NewUIPreviewRecordPresentation.visibleText(
            for: .raw,
            record: record,
            todos: todos
        )
        let todoText = NewUIPreviewRecordPresentation.visibleText(
            for: .todos,
            record: record,
            todos: todos
        )

        XCTAssertTrue(organized.contains("整理摘要"))
        XCTAssertFalse(organized.contains("照片原文"))
        XCTAssertEqual(raw, "照片原文")
        XCTAssertFalse(raw.contains("整理正文"))
        XCTAssertEqual(todoText, "提交纪要\n回复邮件")
        XCTAssertFalse(todoText.contains("照片原文"))
    }

    func testSearchOnlyMatchesCurrentVisibleSection() {
        let record = makeRecord(
            summary: "Design Review",
            detailedContent: "Action plan",
            ocrText: "Whiteboard transcript"
        )

        XCTAssertTrue(NewUIPreviewRecordPresentation.matches(
            query: "design",
            section: .organized,
            record: record,
            todos: []
        ))
        XCTAssertFalse(NewUIPreviewRecordPresentation.matches(
            query: "whiteboard",
            section: .organized,
            record: record,
            todos: []
        ))
        XCTAssertTrue(NewUIPreviewRecordPresentation.matches(
            query: "WHITEBOARD",
            section: .raw,
            record: record,
            todos: []
        ))
    }

    func testEncryptedRecordNeverLeaksToProjectionSearchOrShare() {
        var record = makeRecord(
            summary: "sensitive summary",
            detailedContent: "sensitive detail",
            ocrText: "sensitive raw"
        )
        record.title = "sensitive title"
        record.isEncrypted = true
        let todos = ["sensitive todo"]

        for section in NewUIPreviewRecordDetailSection.allCases {
            XCTAssertEqual(
                NewUIPreviewRecordPresentation.visibleText(
                    for: section,
                    record: record,
                    todos: todos
                ),
                ""
            )
            XCTAssertFalse(NewUIPreviewRecordPresentation.matches(
                query: "sensitive",
                section: section,
                record: record,
                todos: todos
            ))
        }
        XCTAssertEqual(NewUIPreviewRecordPresentation.organizedMarkdown(for: record), "")
        XCTAssertEqual(NewUIPreviewRecordPresentation.shareText(for: record, todos: todos), "")
    }

    private func makeRecord(
        summary: String,
        detailedContent: String,
        ocrText: String = ""
    ) -> NoteRecord {
        NoteRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000941")!,
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000),
            localImagePaths: [],
            title: "测试记录",
            ocrText: ocrText,
            summary: summary,
            detailedContent: detailedContent,
            processingState: .completed,
            source: .photo
        )
    }
}
