import XCTest
@testable import Notiee

@MainActor
final class NotieeStoreTests: XCTestCase {
    func testCapturePhotoStoresRecordAndPersistsIt() throws {
        let recordStore = JSONNoteRecordStore(fileURL: temporaryFileURL())
        let event = ScheduledEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            title: "测试课程",
            startDate: referenceDate.addingTimeInterval(-10 * 60),
            endDate: referenceDate.addingTimeInterval(50 * 60),
            updatedAt: referenceDate.addingTimeInterval(-60 * 60),
            isAllDay: false
        )
        let store = NotieeStore(
            currentDate: referenceDate,
            customEvents: [event],
            todos: [],
            records: [],
            recordStore: recordStore
        )

        let record = store.capturePhoto(localImagePaths: ["test-photo"])

        XCTAssertEqual(store.records, [record])
        XCTAssertEqual(record.eventID, event.id)
        XCTAssertEqual(record.title, "测试课程 拍记")
        XCTAssertEqual(try recordStore.loadRecords(), [record])
        XCTAssertNil(store.lastPersistenceError)
    }

    func testRecordsMatchingSearchesTitleSummaryAndOCRNewestFirst() {
        let older = NoteRecord(
            eventID: nil,
            capturedAt: referenceDate.addingTimeInterval(-60),
            localImagePaths: ["older"],
            title: "白板：旅程图",
            ocrText: "persona journey map",
            summary: "课堂白板记录",
            processingState: .completed
        )
        let newer = NoteRecord(
            eventID: nil,
            capturedAt: referenceDate,
            localImagePaths: ["newer"],
            title: "竞品截图",
            ocrText: "benchmark capture",
            summary: "补充 journey 对比",
            processingState: .pending
        )
        let store = NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: [older, newer],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )

        XCTAssertEqual(store.records(matching: "journey"), [newer, older])
        XCTAssertEqual(store.records(matching: "截图"), [newer])
        XCTAssertEqual(store.records(matching: ""), [newer, older])
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
