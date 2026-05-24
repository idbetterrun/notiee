import XCTest
@testable import Notiee

@MainActor
final class CaptureViewModelTests: XCTestCase {
    func testCaptureCreatesRecordFallbackToUncategorizedWhenNoStore() {
        let viewModel = CaptureViewModel(currentDate: referenceDate)

        let record = viewModel.capturePhoto(localImagePath: "test-capture")

        XCTAssertNil(record.eventID)
        XCTAssertEqual(record.title, "未分类拍记")
        XCTAssertEqual(record.processingState, .pending)
        XCTAssertEqual(record.localImagePaths, ["test-capture"])
        XCTAssertEqual(viewModel.contextTitle, "未分类")
        XCTAssertEqual(viewModel.capturedRecords, [record])
    }

    func testCaptureFallsBackToUncategorizedWhenNoCurrentEvent() {
        let viewModel = CaptureViewModel(currentDate: referenceDate)

        let record = viewModel.capturePhoto(localImagePath: "uncategorized")

        XCTAssertNil(record.eventID)
        XCTAssertEqual(record.title, "未分类拍记")
        XCTAssertEqual(record.processingState, .pending)
        XCTAssertEqual(viewModel.contextTitle, "未分类")
        XCTAssertEqual(viewModel.contextSubtitle, "当前无日程，照片会进入暂存区")
    }

    func testMultipleCapturesAreStoredInOrder() {
        let viewModel = CaptureViewModel(currentDate: referenceDate)

        _ = viewModel.capturePhoto(localImagePath: "capture-1")
        _ = viewModel.capturePhoto(localImagePath: "capture-2")

        XCTAssertEqual(viewModel.capturedRecords.count, 2)
        XCTAssertEqual(viewModel.capturedRecords.map(\.localImagePaths), [
            ["capture-2"],
            ["capture-1"]
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
