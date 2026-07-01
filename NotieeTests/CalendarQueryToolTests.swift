import XCTest
@testable import Notiee

final class CalendarQueryToolTests: XCTestCase {
    private var cal: Calendar { Calendar(identifier: .gregorian) }
    private func baseNow() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 20; c.hour = 10
        return cal.date(from: c)!
    }

    func testToday_rangeIsOneDay() {
        let r = CalendarQueryTool.resolveDateRange(timeRange: "today", startDate: nil, endDate: nil, now: baseNow(), calendar: cal)
        XCTAssertEqual(cal.component(.day, from: r.start), 20)
        XCTAssertEqual(r.end, cal.date(byAdding: .day, value: 1, to: r.start))
    }

    func testTomorrow_startsNextDay() {
        let r = CalendarQueryTool.resolveDateRange(timeRange: "tomorrow", startDate: nil, endDate: nil, now: baseNow(), calendar: cal)
        XCTAssertEqual(cal.component(.day, from: r.start), 21)
        XCTAssertEqual(cal.component(.day, from: cal.date(byAdding: .day, value: -1, to: r.end)!), 21)
    }

    func testCustom_acceptsPlainDate() {
        let r = CalendarQueryTool.resolveDateRange(timeRange: "custom", startDate: "2026-06-25", endDate: "2026-06-27", now: baseNow(), calendar: cal)
        XCTAssertEqual(cal.component(.day, from: r.start), 25)
        XCTAssertEqual(cal.component(.day, from: r.end), 27)
    }

    func testCustom_missingDates_fallsBackToToday() {
        let r = CalendarQueryTool.resolveDateRange(timeRange: "custom", startDate: nil, endDate: nil, now: baseNow(), calendar: cal)
        XCTAssertEqual(cal.component(.day, from: r.start), 20, "缺参应降级为今天，而非抛错")
    }

    func testUnknownRange_fallsBackToToday() {
        let r = CalendarQueryTool.resolveDateRange(timeRange: "garbage", startDate: nil, endDate: nil, now: baseNow(), calendar: cal)
        XCTAssertEqual(cal.component(.day, from: r.start), 20)
    }

    func testParseDate_acceptsCommonDateTimeFormats() {
        XCTAssertNotNil(CalendarQueryTool.parseDate("2026-06-21"))
        XCTAssertNotNil(CalendarQueryTool.parseDate("2026-06-21 10:00"))
        XCTAssertNotNil(CalendarQueryTool.parseDate("2026-06-21T10:00"))
        XCTAssertNotNil(CalendarQueryTool.parseDate("2026-06-21T10:00:00"))
        XCTAssertNil(CalendarQueryTool.parseDate("not a date"))
        XCTAssertNil(CalendarQueryTool.parseDate(nil))
    }
}
