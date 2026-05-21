import XCTest
@testable import Notiee

@MainActor
final class TodayViewModelTests: XCTestCase {
    func testSampleDataIncludesCurrentEventAtReferenceDate() {
        let viewModel = TodayViewModel.sample(currentDate: referenceDate)

        XCTAssertEqual(viewModel.currentEvent?.title, "产品设计课")
        XCTAssertEqual(viewModel.currentEvent?.status(at: referenceDate), .current)
    }

    func testPendingTodosExcludeCompletedItems() {
        let viewModel = TodayViewModel.sample(currentDate: referenceDate)

        XCTAssertEqual(viewModel.pendingTodos.map(\.content), [
            "整理白板上的用户旅程图",
            "补充竞品截图到课程记录"
        ])
    }

    func testTodayRecordsAreFilteredAndNewestFirst() {
        let viewModel = TodayViewModel.sample(currentDate: referenceDate)

        XCTAssertEqual(viewModel.todayRecords.map(\.title), [
            "白板：拍记流程",
            "课件：日程感知"
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
