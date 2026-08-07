import SwiftUI
import UIKit
import XCTest
@testable import Notiee

@MainActor
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

    func testOrganizedMarkdownDoesNotInsertEmptyDetailHeadingBeforeExistingHeading() {
        let record = makeRecord(
            summary: "摘要内容",
            detailedContent: "## 决策\n\n先完成发布节奏。"
        )

        let markdown = NewUIPreviewRecordPresentation.organizedMarkdown(for: record)

        XCTAssertFalse(markdown.contains("## \(String(localized: "详细内容"))\n\n## 决策"))
        XCTAssertTrue(markdown.contains("## 决策\n\n先完成发布节奏。"))
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
        let todoText = NewUIPreviewRecordPresentation.visibleText(
            for: .todos,
            record: record,
            todos: todos
        )

        XCTAssertTrue(organized.contains("整理摘要"))
        XCTAssertFalse(organized.contains("照片原文"))
        XCTAssertEqual(NewUIPreviewRecordPresentation.rawText(for: record), "照片原文")
        XCTAssertFalse(NewUIPreviewRecordPresentation.rawText(for: record).contains("整理正文"))
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
        XCTAssertTrue(NewUIPreviewRecordPresentation.rawMatches(
            query: "WHITEBOARD",
            record: record
        ))
    }

    func testMainSectionsHaveStableOrderAndExcludeRawText() {
        XCTAssertEqual(
            NewUIPreviewRecordDetailSection.allCases,
            [.organized, .todos, .relations]
        )
        XCTAssertEqual(NewUIPreviewRecordPresentation.rawText(for: makeRecord(
            summary: "",
            detailedContent: "",
            ocrText: "独立原文"
        )), "独立原文")
    }

    func testRelationsProjectionIncludesRelatedContentAndReason() throws {
        let state = NewUIPreviewState(startsContextTimer: false)
        let fixture = try XCTUnwrap(state.recordFixtures.first)
        let relations = state.relatedRecords(for: fixture.id)

        let visible = NewUIPreviewRecordPresentation.visibleText(
            for: .relations,
            record: fixture.record,
            todos: fixture.todos,
            relations: relations
        )

        XCTAssertEqual(relations.count, 3)
        XCTAssertTrue(visible.contains(relations[0].fixture.record.title))
        XCTAssertTrue(visible.contains(relations[0].reason.title))
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
        XCTAssertEqual(NewUIPreviewRecordPresentation.rawText(for: record), "")
        XCTAssertFalse(NewUIPreviewRecordPresentation.rawMatches(query: "sensitive", record: record))
        XCTAssertEqual(NewUIPreviewRecordPresentation.shareText(for: record, todos: todos), "")
    }

    func testDetailBackgroundIsOpaqueForTodayAndRecordsOrigins() {
        for origin in [NewUIPreviewRecordOrigin.today, .records] {
            let host = UIHostingController(
                rootView: DetailBackgroundHarness(origin: origin)
                    .frame(width: 96, height: 160)
                    .environment(\.colorScheme, .light)
            )
            host.view.frame = CGRect(x: 0, y: 0, width: 96, height: 160)
            host.view.backgroundColor = .clear
            host.view.layoutIfNeeded()

            let pixels = renderRGBA(view: host.view, width: 96, height: 160)
            let points = [
                CGPoint(x: 1, y: 1),
                CGPoint(x: 94, y: 1),
                CGPoint(x: 48, y: 80),
                CGPoint(x: 1, y: 158),
                CGPoint(x: 94, y: 158)
            ]

            for point in points {
                let index = (Int(point.y) * 96 + Int(point.x)) * 4
                XCTAssertGreaterThan(pixels[index + 1], 245, "origin: \(origin), point: \(point)")
                XCTAssertEqual(pixels[index + 3], 255, "origin: \(origin), point: \(point)")
            }
        }
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

    private func renderRGBA(view: UIView, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        view.layer.render(in: context)
        return pixels
    }
}

private struct DetailBackgroundHarness: View {
    @Namespace private var namespace

    let origin: NewUIPreviewRecordOrigin

    var body: some View {
        ZStack {
            Color(red: 1, green: 0, blue: 1)

            NewUIPreviewRecordDetailBackground(
                recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000941")!,
                origin: origin,
                namespace: namespace
            )
        }
    }
}
