import XCTest
@testable import Notiee

final class CalendarServiceTests: XCTestCase {
    func testStableEventID_isDeterministic() {
        let d = Date(timeIntervalSinceReferenceDate: 100_000)
        let a = CalendarService.stableEventID(eventIdentifier: "EVENT-123", startDate: d)
        let b = CalendarService.stableEventID(eventIdentifier: "EVENT-123", startDate: d)
        XCTAssertEqual(a, b, "相同 identifier+startDate 必须得到相同 UUID")
    }

    func testStableEventID_differsByIdentifier() {
        let d = Date(timeIntervalSinceReferenceDate: 100_000)
        XCTAssertNotEqual(
            CalendarService.stableEventID(eventIdentifier: "A", startDate: d),
            CalendarService.stableEventID(eventIdentifier: "B", startDate: d))
    }

    func testStableEventID_differsByOccurrenceDate() {
        XCTAssertNotEqual(
            CalendarService.stableEventID(eventIdentifier: "A", startDate: Date(timeIntervalSinceReferenceDate: 0)),
            CalendarService.stableEventID(eventIdentifier: "A", startDate: Date(timeIntervalSinceReferenceDate: 86_400)))
    }

    func testStableEventID_nilIdentifier_doesNotCrash() {
        _ = CalendarService.stableEventID(eventIdentifier: nil, startDate: Date())
    }
}
