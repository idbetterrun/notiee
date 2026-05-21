import XCTest
@testable import Notiee

final class ScheduleMatcherTests: XCTestCase {
    func testReturnsNilWhenNoEventContainsCurrentDate() {
        let now = date(hour: 10)
        let event = ScheduledEvent(
            title: "线性代数",
            startDate: date(hour: 8),
            endDate: date(hour: 9),
            updatedAt: date(hour: 7)
        )

        let result = ScheduleMatcher().currentEvent(from: [event], at: now)

        XCTAssertNil(result)
    }

    func testReturnsEventContainingCurrentDate() {
        let now = date(hour: 10, minute: 30)
        let event = ScheduledEvent(
            title: "产品例会",
            startDate: date(hour: 10),
            endDate: date(hour: 11),
            kind: .meeting,
            updatedAt: date(hour: 9)
        )

        let result = ScheduleMatcher().currentEvent(from: [event], at: now)

        XCTAssertEqual(result?.title, "产品例会")
    }

    func testPrefersMostRecentlyUpdatedEventWhenSchedulesOverlap() {
        let now = date(hour: 14, minute: 20)
        let older = ScheduledEvent(
            title: "机器学习",
            startDate: date(hour: 14),
            endDate: date(hour: 15),
            updatedAt: date(hour: 8)
        )
        let newer = ScheduledEvent(
            title: "项目讨论",
            startDate: date(hour: 14),
            endDate: date(hour: 15),
            kind: .meeting,
            updatedAt: date(hour: 12)
        )

        let result = ScheduleMatcher().currentEvent(from: [older, newer], at: now)

        XCTAssertEqual(result?.title, "项目讨论")
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 5
        components.day = 21
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}
