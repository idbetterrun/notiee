import XCTest
@testable import Notiee

final class TodoBucketerTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func now() -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 23; c.hour = 10
        return cal.date(from: c)!
    }
    private func todo(due offsetDays: Int?) -> NoteTodo {
        let d = offsetDays.map { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now()))! }
        return NoteTodo(recordID: nil, content: "t", dueDate: d)
    }

    func testBuckets() {
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: -1), now: now(), calendar: cal), .overdue)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: 0),  now: now(), calendar: cal), .today)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: 1),  now: now(), calendar: cal), .tomorrow)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: 4),  now: now(), calendar: cal), .thisWeek)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: 30), now: now(), calendar: cal), .later)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: nil), now: now(), calendar: cal), .noDueDate)
    }

    func testIsActionableNow() {
        XCTAssertTrue(TodoBucketer.isActionableNow(todo(due: -1), now: now(), calendar: cal))
        XCTAssertTrue(TodoBucketer.isActionableNow(todo(due: 0),  now: now(), calendar: cal))
        XCTAssertTrue(TodoBucketer.isActionableNow(todo(due: nil), now: now(), calendar: cal))
        XCTAssertFalse(TodoBucketer.isActionableNow(todo(due: 3), now: now(), calendar: cal))
    }
}
