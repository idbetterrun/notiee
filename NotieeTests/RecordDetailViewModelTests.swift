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
            events: [event],
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
