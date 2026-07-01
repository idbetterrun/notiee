import XCTest
@testable import Notiee

@MainActor
final class ScheduleUpdateToolTests: XCTestCase {

    private func makeManager(events: [ScheduledEvent]) -> CalendarManager {
        let store = JSONScheduledEventStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json"))
        return CalendarManager(
            currentDate: Date(),
            calendar: Calendar(identifier: .gregorian),
            customEvents: events,
            eventStore: store,
            persistedRecordsProvider: { [] }
        )
    }

    func testUpdate_localEvent_succeeds() async throws {
        let event = ScheduledEvent(
            title: "Old",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            source: .ai
        )
        let mgr = makeManager(events: [event])
        let tool = ScheduleUpdateTool(calendarManager: mgr)
        let result = try await tool.execute(parameters: [
            "event_id": event.id.uuidString,
            "title": "New"
        ])
        XCTAssertTrue(result.success)
        XCTAssertTrue(mgr.allEvents.contains { $0.id == event.id && $0.title == "New" })
        XCTAssertNotNil(result.undoAction, "修改应提供撤销动作")
    }

    func testUpdate_systemEvent_returnsGuidanceNotError() async throws {
        let sys = ScheduledEvent(
            title: "Sys",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            source: .systemCalendar(identifier: "X")
        )
        // 系统事件正常不在 customEvents，这里仅构造用于走系统日历分支
        let mgr = makeManager(events: [sys])
        let tool = ScheduleUpdateTool(calendarManager: mgr)
        let result = try await tool.execute(parameters: [
            "event_id": sys.id.uuidString,
            "title": "New"
        ])
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.message.contains("系统"))
    }

    func testUpdate_missingEventID_throws() async {
        let mgr = makeManager(events: [])
        let tool = ScheduleUpdateTool(calendarManager: mgr)
        do {
            _ = try await tool.execute(parameters: ["title": "New"])
            XCTFail("缺 event_id 应抛错")
        } catch is AgentToolError {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUpdate_unknownEvent_returnsFailure() async throws {
        let mgr = makeManager(events: [])
        let tool = ScheduleUpdateTool(calendarManager: mgr)
        let result = try await tool.execute(parameters: [
            "event_id": UUID().uuidString,
            "title": "New"
        ])
        XCTAssertFalse(result.success)
    }
}
