import XCTest
@testable import Notiee

@MainActor
final class CaptureViewModelTests: XCTestCase {
    func testCaptureCreatesRecordAttachedToCurrentEvent() {
        let event = ScheduledEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            title: "产品设计课",
            startDate: referenceDate.addingTimeInterval(-10 * 60),
            endDate: referenceDate.addingTimeInterval(50 * 60),
            updatedAt: referenceDate.addingTimeInterval(-60 * 60)
        )
        let viewModel = CaptureViewModel(currentDate: referenceDate, events: [event])

        let record = viewModel.capturePhoto(localImagePath: "mock://capture-1")

        XCTAssertEqual(record.eventID, event.id)
        XCTAssertEqual(record.title, "产品设计课 拍记")
        XCTAssertEqual(record.processingState, .pending)
        XCTAssertEqual(record.localImagePath, "mock://capture-1")
        XCTAssertEqual(viewModel.contextTitle, "产品设计课")
        XCTAssertEqual(viewModel.capturedRecords, [record])
    }

    func testCaptureFallsBackToUncategorizedWhenNoCurrentEvent() {
        let viewModel = CaptureViewModel(currentDate: referenceDate, events: [])

        let record = viewModel.capturePhoto(localImagePath: "mock://uncategorized")

        XCTAssertNil(record.eventID)
        XCTAssertEqual(record.title, "未分类拍记")
        XCTAssertEqual(record.processingState, .pending)
        XCTAssertEqual(viewModel.contextTitle, "未分类")
        XCTAssertEqual(viewModel.contextSubtitle, "当前无日程，照片会进入暂存区")
    }

    func testLatestRecordUsesNewestCapture() {
        let viewModel = CaptureViewModel(currentDate: referenceDate, events: [])

        _ = viewModel.capturePhoto(localImagePath: "mock://capture-1")
        let newest = viewModel.capturePhoto(localImagePath: "mock://capture-2")

        XCTAssertEqual(viewModel.latestRecord, newest)
        XCTAssertEqual(viewModel.capturedRecords.map(\.localImagePath), [
            "mock://capture-2",
            "mock://capture-1"
        ])
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
