import XCTest
@testable import Notiee

@MainActor
final class DateInfoToolTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func makeTool() -> DateInfoTool {
        DateInfoTool(now: { self.cal.date(from: DateComponents(year: 2026, month: 6, day: 22))! },
                     calendar: self.cal)
    }

    func testExplicitDate_weekday() async throws {
        let r = try await makeTool().execute(parameters: ["date": "2026-06-24"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.message.contains("星期三"), "2026-06-24 应为星期三，实际: \(r.message)")
    }

    func testToday() async throws {
        let r = try await makeTool().execute(parameters: ["date": "today"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.message.contains("星期一"), "2026-06-22 应为星期一，实际: \(r.message)")
    }

    func testOffsetDays() async throws {
        let r = try await makeTool().execute(parameters: ["date": "2026-06-24"])
        XCTAssertEqual(r.data?["offset_days"] as? Int, 2)
    }

    func testMissingParam_throws() async {
        do { _ = try await makeTool().execute(parameters: [:]); XCTFail("应抛出") }
        catch {}
    }

    func testUnparseable_returnsFailure() async throws {
        let r = try await makeTool().execute(parameters: ["date": "随便写点啥"])
        XCTAssertFalse(r.success)
    }
}
