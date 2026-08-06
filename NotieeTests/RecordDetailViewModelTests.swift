import XCTest
@testable import Notiee

@MainActor
final class RecordDetailViewModelTests: XCTestCase {
    func testDetailResolvesEventTitleSummaryOCRAndTodos() {
        let recordID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let event = ScheduledEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            title: "测试课程",
            startDate: referenceDate.addingTimeInterval(-30 * 60),
            endDate: referenceDate.addingTimeInterval(30 * 60),
            isAllDay: false
        )
        let record = NoteRecord(
            id: recordID,
            eventID: event.id,
            capturedAt: referenceDate,
            localImagePaths: ["detail"],
            title: "白板：用户旅程",
            ocrText: "",
            summary: "",
            processingState: .pending
        )
        let olderTodo = NoteTodo(
            recordID: recordID,
            content: "整理用户旅程图",
            createdAt: referenceDate.addingTimeInterval(-120)
        )
        let newerTodo = NoteTodo(
            recordID: recordID,
            content: "补充竞品截图",
            createdAt: referenceDate.addingTimeInterval(-60)
        )
        let unrelatedTodo = NoteTodo(
            recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
            content: "不应显示",
            createdAt: referenceDate
        )
        let store = NotieeStore(
            currentDate: referenceDate,
            customEvents: [event],
            todos: [newerTodo, unrelatedTodo, olderTodo],
            records: [record],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )

        let viewModel = RecordDetailViewModel(record: record, store: store)

        XCTAssertEqual(viewModel.eventTitle, "测试课程")
        XCTAssertEqual(viewModel.summaryText, "AI 正在整理这条记录。")
        XCTAssertEqual(viewModel.ocrText, "OCR 结果生成后会显示在这里。")
        XCTAssertEqual(viewModel.todos.map(\.content), [
            "整理用户旅程图",
            "补充竞品截图"
        ])
        XCTAssertEqual(viewModel.statusTitle, "等待 AI 处理")
    }

    func testDetailFallsBackToUncategorizedWhenNoEventExists() {
        let record = NoteRecord(
            eventID: nil,
            capturedAt: referenceDate,
            localImagePaths: ["uncategorized"],
            title: "未分类拍记",
            ocrText: "whiteboard notes",
            summary: "拍摄了白板上的流程草图。",
            processingState: .completed
        )
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [record],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )

        let viewModel = RecordDetailViewModel(record: record, store: store)

        XCTAssertEqual(viewModel.eventTitle, "未分类")
        XCTAssertEqual(viewModel.summaryText, "拍摄了白板上的流程草图。")
        XCTAssertEqual(viewModel.ocrText, "whiteboard notes")
        XCTAssertEqual(viewModel.statusTitle, "已生成摘要")
    }

    // MARK: - 区块可见性（按来源）

    private func vm(for record: NoteRecord) -> RecordDetailViewModel {
        let store = NotieeStore(
            currentDate: referenceDate,
            todos: [],
            records: [record],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )
        return RecordDetailViewModel(record: record, store: store)
    }

    func testPhotoRecord_showsSummaryOCRAndTodoPlaceholder() {
        let r = NoteRecord(localImagePaths: ["x"], title: "拍照", source: .photo)
        let m = vm(for: r)
        XCTAssertTrue(m.showsSummarySection)
        XCTAssertTrue(m.showsOCRSection)
        XCTAssertTrue(m.showsTodoPlaceholder)
    }

    func testTextRecord_hidesSummaryOCRAndPlaceholder() {
        let r = NoteRecord(localImagePaths: [], title: "纯文本", summary: "", detailedContent: "正文", source: .text)
        let m = vm(for: r)
        XCTAssertFalse(m.showsSummarySection)
        XCTAssertFalse(m.showsOCRSection)
        XCTAssertFalse(m.showsTodoPlaceholder)
    }

    func testNottiRecord_showsSummaryOnlyWhenRealSummaryDiffersFromContent() {
        let withReal = NoteRecord(localImagePaths: [], title: "S", summary: "一句话摘要", detailedContent: "很长的正文", source: .notti)
        XCTAssertTrue(vm(for: withReal).showsSummarySection)

        let noSummary = NoteRecord(localImagePaths: [], title: "S", summary: "", detailedContent: "正文", source: .notti)
        XCTAssertFalse(vm(for: noSummary).showsSummarySection)

        let dup = NoteRecord(localImagePaths: [], title: "S", summary: "正文", detailedContent: "正文", source: .notti)
        XCTAssertFalse(vm(for: dup).showsSummarySection, "摘要等于正文时不展示")

        // Notti 记录无图，OCR 始终隐藏
        XCTAssertFalse(vm(for: withReal).showsOCRSection)
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private var referenceDate: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        components.year = 2026
        components.month = 5
        components.day = 21
        components.hour = 10
        components.minute = 30
        return components.date!
    }
}
