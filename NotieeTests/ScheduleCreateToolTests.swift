import XCTest
@testable import Notiee

@MainActor
final class ScheduleCreateToolTests: XCTestCase {

    // 与 CalendarManagerTests 一致：用临时文件 store 构造真实 CalendarManager
    private func makeManager() -> CalendarManager {
        let store = JSONScheduledEventStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json"))
        return CalendarManager(
            currentDate: Date(),
            calendar: Calendar(identifier: .gregorian),
            customEvents: [],
            eventStore: store,
            persistedRecordsProvider: { [] }
        )
    }

    func testCreate_addsEventToManager() async throws {
        let mgr = makeManager()
        let tool = ScheduleCreateTool(calendarManager: mgr)
        let result = try await tool.execute(parameters: [
            "title": "Date at PKU",
            "start_date": "2026-06-21T19:00:00Z"
        ])
        XCTAssertTrue(result.success)
        XCTAssertTrue(mgr.allEvents.contains { $0.title == "Date at PKU" })
        XCTAssertNotNil(result.undoAction, "创建应提供撤销动作")
    }

    func testCreate_missingTitle_throws() async {
        let mgr = makeManager()
        let tool = ScheduleCreateTool(calendarManager: mgr)
        do {
            _ = try await tool.execute(parameters: ["start_date": "2026-06-21T19:00:00Z"])
            XCTFail("缺 title 应抛错")
        } catch let e as AgentToolError {
            XCTAssertEqual(e.errorDescription, "缺少必要参数：title")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreate_defaultsEndOneHourAfterStart() async throws {
        let mgr = makeManager()
        let tool = ScheduleCreateTool(calendarManager: mgr)
        _ = try await tool.execute(parameters: [
            "title": "Meeting",
            "start_date": "2026-06-21T19:00:00Z"
        ])
        let event = mgr.allEvents.first { $0.title == "Meeting" }!
        XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 3600, accuracy: 1)
    }
}
