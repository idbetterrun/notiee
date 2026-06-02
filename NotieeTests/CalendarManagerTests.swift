import XCTest
@testable import Notiee

@MainActor
final class CalendarManagerTests: XCTestCase {

    // MARK: - Event Management

    func testAddEvent() {
        let mgr = makeManager()
        let event = makeEvent(title: "New Event")
        mgr.addEvent(event)
        XCTAssertTrue(mgr.allEvents.contains(where: { $0.title == "New Event" }))
        XCTAssertTrue(mgr.events.contains(where: { $0.title == "New Event" }))
    }

    func testDeleteEvent() {
        let event = makeEvent(title: "ToDelete")
        let mgr = makeManager(customEvents: [event])
        mgr.deleteEvent(id: event.id)
        XCTAssertFalse(mgr.allEvents.contains(where: { $0.id == event.id }))
    }

    func testIgnoreCalendarEventOnce() {
        let event = makeEvent(source: .systemCalendar(identifier: "CAL-001"))
        let mgr = makeManager()
        mgr.ignoreCalendarEvent(identifier: "CAL-001", date: event.startDate, future: false)
        XCTAssertTrue(mgr.isEventIgnored(event))
    }

    func testIgnoreCalendarEventFuture() {
        let event = makeEvent(source: .systemCalendar(identifier: "CAL-002"))
        let mgr = makeManager()
        mgr.ignoreCalendarEvent(identifier: "CAL-002", date: event.startDate, future: true)
        XCTAssertTrue(mgr.isEventIgnored(event))
    }

    func testIgnoreCalendarEventIsNotIgnoredWhenNotIgnored() {
        let event = makeEvent(source: .systemCalendar(identifier: "CAL-003"))
        let mgr = makeManager()
        XCTAssertFalse(mgr.isEventIgnored(event))
    }

    func testRestoreCalendarEvent() {
        let event = makeEvent(source: .systemCalendar(identifier: "CAL-004"))
        let mgr = makeManager()
        mgr.ignoreCalendarEvent(identifier: "CAL-004", date: event.startDate, future: true)
        XCTAssertTrue(mgr.isEventIgnored(event))
        mgr.restoreCalendarEvent(identifier: "CAL-004")
        XCTAssertFalse(mgr.isEventIgnored(event))
    }

    func testRestoreCalendarEventOnlyRemovesMatchingIdentifier() {
        let eventA = makeEvent(source: .systemCalendar(identifier: "CAL-A"))
        let eventB = makeEvent(source: .systemCalendar(identifier: "CAL-B"))
        let mgr = makeManager()
        mgr.ignoreCalendarEvent(identifier: "CAL-A", date: eventA.startDate, future: true)
        mgr.ignoreCalendarEvent(identifier: "CAL-B", date: eventB.startDate, future: true)
        mgr.restoreCalendarEvent(identifier: "CAL-A")
        XCTAssertFalse(mgr.isEventIgnored(eventA))
        XCTAssertTrue(mgr.isEventIgnored(eventB))
    }

    // MARK: - Computed Properties

    func testCurrentEventWhenNoEvents() {
        let mgr = makeManager()
        XCTAssertNil(mgr.currentEvent)
    }

    func testCurrentEventFindsEventContainingNow() {
        let now = Date()
        let event = ScheduledEvent(
            title: "Current",
            startDate: now.addingTimeInterval(-10 * 60),
            endDate: now.addingTimeInterval(50 * 60),
            isAllDay: false
        )
        let mgr = makeManager(currentDate: now, customEvents: [event])
        XCTAssertEqual(mgr.currentEvent?.title, "Current")
    }

    func testEventsWithRecordsReturnsEmptyWhenNoRecords() {
        let mgr = makeManager()
        XCTAssertTrue(mgr.eventsWithRecords.isEmpty)
    }

    func testFormattedDateWithWeek() {
        let mgr = makeManager()
        let result = mgr.formattedDateWithWeek(for: ref)
        XCTAssertTrue(result.contains("2026") || result.contains("5月") || result.contains("21"), "Got: (result)")
        
    }

    func testEventTitleForRecord() {
        let event = makeEvent(title: "Math 101")
        let record = NoteRecord(
            eventID: event.id,
            capturedAt: ref,
            localImagePaths: [],
            title: "Note",
            processingState: .completed
        )
        let mgr = makeManager(customEvents: [event], records: [record])
        XCTAssertEqual(mgr.eventTitle(for: record), "Math 101")
    }

    func testEventTitleReturnsNilForNilEventID() {
        let record = NoteRecord(
            eventID: nil,
            capturedAt: ref,
            localImagePaths: [],
            title: "Note",
            processingState: .completed
        )
        let mgr = makeManager()
        XCTAssertNil(mgr.eventTitle(for: record))
    }

    // MARK: - Tag References

    func testClearTagReferences() {
        let tagID = UUID()
        var event = makeEvent(title: "Tagged")
        event.tagID = tagID
        let mgr = makeManager(customEvents: [event])
        mgr.clearTagReferences(for: tagID)
        XCTAssertNil(mgr.events.first?.tagID)
    }

    func testUpdateEventTag() {
        let tagID = UUID()
        var event = makeEvent(title: "Tagged")
        let mgr = makeManager(customEvents: [event])
        mgr.updateEventTag(eventID: event.id, tagID: tagID)
        XCTAssertEqual(mgr.events.first?.tagID, tagID)
    }

    // MARK: - Persistence

    func testPersistIgnoredKeys() {
        let event = makeEvent(source: .systemCalendar(identifier: "CAL-P"))
        let mgr = makeManager()
        mgr.ignoreCalendarEvent(identifier: "CAL-P", date: event.startDate, future: true)
        // Verify it was saved to UserDefaults
        let data = UserDefaults.standard.data(forKey: UDK.ignoredCalendarEventKeys)
        XCTAssertNotNil(data)
        let decoded = try? JSONDecoder().decode(Set<String>.self, from: data!)
        XCTAssertTrue(decoded?.contains(where: { $0.contains("CAL-P") }) ?? false)
    }

    // MARK: - Helpers

    private var ref: Date {
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

    private func makeManager(
        currentDate: Date? = nil,
        customEvents: [ScheduledEvent] = [],
        records: [NoteRecord] = []
    ) -> CalendarManager {
        CalendarManager(
            currentDate: currentDate ?? ref,
            calendar: Calendar(identifier: .gregorian),
            customEvents: customEvents,
            eventStore: makeEventStore(),
            persistedRecordsProvider: { records }
        )
    }

    private func makeEventStore() -> JSONScheduledEventStore {
        JSONScheduledEventStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json"))
    }

    private func makeEvent(title: String = "Test Event", source: EventSource = .notiee) -> ScheduledEvent {
        ScheduledEvent(
            title: title,
            startDate: ref.addingTimeInterval(-10 * 60),
            endDate: ref.addingTimeInterval(50 * 60),
            source: source,
            isAllDay: false
        )
    }
}
