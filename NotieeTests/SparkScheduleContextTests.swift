import XCTest
@testable import Notiee

final class SparkScheduleContextTests: XCTestCase {
    private var cal: Calendar { Calendar(identifier: .gregorian) }
    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h
        return cal.date(from: c)!
    }
    private func event(_ title: String, _ date: Date, allDay: Bool = false) -> ScheduledEvent {
        ScheduledEvent(title: title, startDate: date, endDate: date.addingTimeInterval(3600),
                       kind: .meeting, source: .notiee, isAllDay: allDay)
    }

    func testEmpty_returnsNoScheduleText() {
        let block = SparkAIService.upcomingScheduleBlock(
            events: [], now: at(2026, 6, 22), calendar: cal, windowDays: 7, cap: 20)
        XCTAssertTrue(block.contains("未来 7 天没有日程"))
    }

    func testIncludesEventsInsideWindowSortedAscending() {
        let now = at(2026, 6, 22, 8)
        let events = [
            event("晚会", at(2026, 6, 24, 19)),
            event("晨会", at(2026, 6, 23, 9)),
        ]
        let block = SparkAIService.upcomingScheduleBlock(
            events: events, now: now, calendar: cal, windowDays: 7, cap: 20)
        let morningIdx = block.range(of: "晨会")!.lowerBound
        let eveningIdx = block.range(of: "晚会")!.lowerBound
        XCTAssertLessThan(morningIdx, eveningIdx, "应按时间升序")
    }

    func testExcludesEventsOutsideWindow() {
        let now = at(2026, 6, 22, 8)
        let events = [
            event("窗口内", at(2026, 6, 25, 9)),
            event("窗口外", at(2026, 7, 30, 9)),
            event("已过去", at(2026, 6, 21, 9)),
        ]
        let block = SparkAIService.upcomingScheduleBlock(
            events: events, now: now, calendar: cal, windowDays: 7, cap: 20)
        XCTAssertTrue(block.contains("窗口内"))
        XCTAssertFalse(block.contains("窗口外"))
        XCTAssertFalse(block.contains("已过去"))
    }

    func testCapsResultCount() {
        let now = at(2026, 6, 22, 0)
        let events = (0..<30).map { event("E\($0)", at(2026, 6, 22, 1).addingTimeInterval(Double($0) * 600)) }
        let block = SparkAIService.upcomingScheduleBlock(
            events: events, now: now, calendar: cal, windowDays: 7, cap: 20)
        let lines = block.split(separator: "\n").filter { $0.contains(" - ") }
        XCTAssertLessThanOrEqual(lines.count, 20)
    }
}
