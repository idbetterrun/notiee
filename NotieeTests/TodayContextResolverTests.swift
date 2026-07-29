import XCTest
@testable import Notiee

final class TodayContextResolverTests: XCTestCase {
    private let resolver = TodayContextResolver()

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
        return cal
    }

    private var now: Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = 2026
        components.month = 7
        components.day = 29
        components.hour = 10
        components.minute = 0
        components.second = 0
        return components.date!
    }

    // MARK: - Fixtures

    private func makeEvent(
        title: String = "Event",
        start: Date,
        end: Date
    ) -> ScheduledEvent {
        ScheduledEvent(title: title, startDate: start, endDate: end, updatedAt: start)
    }

    private func makeTodo(
        content: String = "Todo",
        isCompleted: Bool = false,
        createdAt: Date? = nil,
        dueDate: Date? = nil
    ) -> NoteTodo {
        NoteTodo(recordID: nil, content: content, isCompleted: isCompleted, createdAt: createdAt ?? now, dueDate: dueDate)
    }

    private func makeRecord(
        capturedAt: Date,
        isDeleted: Bool = false
    ) -> NoteRecord {
        NoteRecord(capturedAt: capturedAt, localImagePaths: [], isDeleted: isDeleted)
    }

    private func threeTodayRecords() -> [NoteRecord] {
        [
            makeRecord(capturedAt: now.addingTimeInterval(-60)),
            makeRecord(capturedAt: now.addingTimeInterval(-120)),
            makeRecord(capturedAt: now.addingTimeInterval(-180))
        ]
    }

    // MARK: - Priority 1: active event beats everything

    func testActiveEventWinsOverEveryOtherContext() {
        let active = makeEvent(title: "Active", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))
        let imminent = makeEvent(title: "Imminent", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1800))
        let overdue = makeTodo(content: "Overdue", dueDate: now.addingTimeInterval(-3600))

        let state = resolver.resolve(
            now: now,
            events: [active, imminent],
            todos: [overdue],
            records: threeTodayRecords(),
            calendar: calendar
        )

        XCTAssertEqual(state.hero, .activeEvent(active))
    }

    // MARK: - Priority 2: due/overdue todo beats imminent event and records

    func testOverdueTodoWinsOverImminentEventAndRecords() {
        let imminent = makeEvent(title: "Imminent", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1800))
        let overdue = makeTodo(content: "Overdue", dueDate: now.addingTimeInterval(-3600))

        let state = resolver.resolve(
            now: now,
            events: [imminent],
            todos: [overdue],
            records: threeTodayRecords(),
            calendar: calendar
        )

        XCTAssertEqual(state.hero, .dueTodo(overdue))
    }

    func testDueSoonTodoWithinTwoHoursWinsOverImminentEvent() {
        let imminent = makeEvent(title: "Imminent", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1800))
        // Due exactly at now + 2h boundary (inclusive)
        let dueSoon = makeTodo(content: "DueSoon", dueDate: now.addingTimeInterval(2 * 60 * 60))

        let state = resolver.resolve(
            now: now,
            events: [imminent],
            todos: [dueSoon],
            records: [],
            calendar: calendar
        )

        XCTAssertEqual(state.hero, .dueTodo(dueSoon))
    }

    func testTodoDueJustBeyondTwoHoursDoesNotQualifyAsHero() {
        let imminent = makeEvent(title: "Imminent", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1800))
        let farDue = makeTodo(content: "FarDue", dueDate: now.addingTimeInterval(2 * 60 * 60 + 1))

        let state = resolver.resolve(
            now: now,
            events: [imminent],
            todos: [farDue],
            records: [],
            calendar: calendar
        )

        XCTAssertEqual(state.hero, .imminentEvent(imminent))
    }

    // MARK: - Priority 3: imminent event beats records

    func testImminentEventWinsOverRecordMomentum() {
        let imminent = makeEvent(title: "Imminent", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1800))

        let state = resolver.resolve(
            now: now,
            events: [imminent],
            todos: [],
            records: threeTodayRecords(),
            calendar: calendar
        )

        XCTAssertEqual(state.hero, .imminentEvent(imminent))
    }

    func testEventStartingExactlyAtNowIsNotImminent() {
        // status(at:) would treat startDate == now as .current (contains uses <=), so this
        // event should already be picked up as an activeEvent, not an imminentEvent.
        let atNow = makeEvent(title: "AtNow", start: now, end: now.addingTimeInterval(1800))

        let state = resolver.resolve(now: now, events: [atNow], todos: [], records: [], calendar: calendar)

        XCTAssertEqual(state.hero, .activeEvent(atNow))
    }

    func testEventStartingBeyondThirtyMinutesIsNotImminent() {
        let farEvent = makeEvent(title: "Far", start: now.addingTimeInterval(30 * 60 + 1), end: now.addingTimeInterval(60 * 60))

        let state = resolver.resolve(now: now, events: [farEvent], todos: [], records: [], calendar: calendar)

        XCTAssertEqual(state.hero, .calm)
    }

    func testEventStartingExactlyAtThirtyMinutesIsImminent() {
        let boundaryEvent = makeEvent(title: "Boundary", start: now.addingTimeInterval(30 * 60), end: now.addingTimeInterval(60 * 60))

        let state = resolver.resolve(now: now, events: [boundaryEvent], todos: [], records: [], calendar: calendar)

        XCTAssertEqual(state.hero, .imminentEvent(boundaryEvent))
    }

    // MARK: - Priority 4: three or more today records -> record momentum

    func testThreeTodayRecordsChoosesRecordMomentum() {
        let records = threeTodayRecords()

        let state = resolver.resolve(now: now, events: [], todos: [], records: records, calendar: calendar)

        XCTAssertEqual(state.hero, .recordMomentum(count: 3))
    }

    func testTwoTodayRecordsDoesNotQualifyForMomentum() {
        let records = [
            makeRecord(capturedAt: now.addingTimeInterval(-60)),
            makeRecord(capturedAt: now.addingTimeInterval(-120))
        ]

        let state = resolver.resolve(now: now, events: [], todos: [], records: records, calendar: calendar)

        XCTAssertEqual(state.hero, .calm)
    }

    func testDeletedRecordsAreExcludedFromMomentumCount() {
        let records = [
            makeRecord(capturedAt: now.addingTimeInterval(-60)),
            makeRecord(capturedAt: now.addingTimeInterval(-120)),
            makeRecord(capturedAt: now.addingTimeInterval(-180), isDeleted: true),
            makeRecord(capturedAt: now.addingTimeInterval(-240), isDeleted: true)
        ]

        let state = resolver.resolve(now: now, events: [], todos: [], records: records, calendar: calendar)

        XCTAssertEqual(state.hero, .calm)
        XCTAssertEqual(state.todayRecordCount, 2)
    }

    // MARK: - Priority 5: empty data -> calm

    func testEmptyDataChoosesCalm() {
        let state = resolver.resolve(now: now, events: [], todos: [], records: [], calendar: calendar)

        XCTAssertEqual(state.hero, .calm)
        XCTAssertEqual(state.todayRecordCount, 0)
        XCTAssertEqual(state.actionableTodoCount, 0)
        XCTAssertTrue(state.urgentTodos.isEmpty)
        XCTAssertTrue(state.urgentEvents.isEmpty)
        if case .records(let records) = state.review {
            XCTAssertTrue(records.isEmpty)
        } else {
            XCTFail("Calm hero should surface a records review slot")
        }
    }

    // MARK: - Supporting data caps

    func testCapsEverySupportingSlotAndExcludesHeroItem() {
        let active = makeEvent(title: "Active", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))
        let imminentEvents = (0..<4).map {
            makeEvent(title: "Imminent\($0)", start: now.addingTimeInterval(Double($0) * 60 + 60), end: now.addingTimeInterval(1800))
        }
        let overdueTodos = (0..<4).map {
            makeTodo(content: "Overdue\($0)", dueDate: now.addingTimeInterval(Double(-$0 - 1) * 60))
        }
        let events = [active] + imminentEvents
        let todos = overdueTodos

        let state = resolver.resolve(now: now, events: events, todos: todos, records: [], calendar: calendar)

        XCTAssertEqual(state.hero, .activeEvent(active))
        XCTAssertLessThanOrEqual(state.urgentTodos.count, 2)
        XCTAssertLessThanOrEqual(state.urgentEvents.count, 2)
        XCTAssertEqual(state.urgentTodos.count, 2)
        XCTAssertEqual(state.urgentEvents.count, 2)
    }

    func testUrgentTodosExcludeTheHeroTodoWhenHeroIsDueTodo() {
        // The most overdue (earliest due date) todo becomes the Hero; a less-overdue
        // due-soon todo remains a candidate for the urgentTodos supporting slot.
        let heroTodo = makeTodo(content: "Hero", dueDate: now.addingTimeInterval(-120))
        let otherOverdue = makeTodo(content: "Other", dueDate: now.addingTimeInterval(-60))

        let state = resolver.resolve(now: now, events: [], todos: [heroTodo, otherOverdue], records: [], calendar: calendar)

        XCTAssertEqual(state.hero, .dueTodo(heroTodo))
        XCTAssertFalse(state.urgentTodos.contains(heroTodo))
        XCTAssertTrue(state.urgentTodos.contains(otherOverdue))
    }

    func testUrgentEventsExcludeTheHeroEventWhenHeroIsImminentEvent() {
        let heroEvent = makeEvent(title: "Hero", start: now.addingTimeInterval(60), end: now.addingTimeInterval(1800))
        let otherImminent = makeEvent(title: "Other", start: now.addingTimeInterval(120), end: now.addingTimeInterval(1800))

        let state = resolver.resolve(now: now, events: [heroEvent, otherImminent], todos: [], records: [], calendar: calendar)

        XCTAssertEqual(state.hero, .imminentEvent(heroEvent))
        XCTAssertFalse(state.urgentEvents.contains(heroEvent))
        XCTAssertTrue(state.urgentEvents.contains(otherImminent))
    }

    // MARK: - Review slot: execution hero -> todos

    func testActiveEventHeroProducesTodosReviewSlotCappedAtThree() {
        let active = makeEvent(title: "Active", start: now.addingTimeInterval(-600), end: now.addingTimeInterval(600))
        let actionableTodos = (0..<5).map { makeTodo(content: "Actionable\($0)") } // no due date -> actionable now
        let completedTodo = makeTodo(content: "Completed", isCompleted: true)

        let state = resolver.resolve(
            now: now,
            events: [active],
            todos: actionableTodos + [completedTodo],
            records: [],
            calendar: calendar
        )

        guard case .todos(let review) = state.review else {
            return XCTFail("Expected todos review slot for active event hero")
        }
        XCTAssertEqual(review.count, 3)
        XCTAssertFalse(review.contains(completedTodo))
    }

    func testDueTodoHeroExcludesItsOwnTodoFromTodosReviewSlot() {
        let heroTodo = makeTodo(content: "Hero", dueDate: now.addingTimeInterval(-60))
        let otherActionable = makeTodo(content: "Other")

        let state = resolver.resolve(now: now, events: [], todos: [heroTodo, otherActionable], records: [], calendar: calendar)

        guard case .todos(let review) = state.review else {
            return XCTFail("Expected todos review slot for dueTodo hero")
        }
        XCTAssertFalse(review.contains(heroTodo))
        XCTAssertTrue(review.contains(otherActionable))
    }

    // MARK: - Review slot: reflection/calm hero -> records

    func testRecordMomentumHeroProducesRecordsReviewSlotCappedAtThreeMostRecentFirst() {
        let records = (0..<5).map { makeRecord(capturedAt: now.addingTimeInterval(Double(-$0) * 60)) }

        let state = resolver.resolve(now: now, events: [], todos: [], records: records, calendar: calendar)

        XCTAssertEqual(state.hero, .recordMomentum(count: 5))
        guard case .records(let review) = state.review else {
            return XCTFail("Expected records review slot for recordMomentum hero")
        }
        XCTAssertEqual(review.count, 3)
        XCTAssertEqual(review, Array(records.prefix(3)))
    }

    func testCalmHeroProducesRecordsReviewSlot() {
        let records = [makeRecord(capturedAt: now.addingTimeInterval(-60))]

        let state = resolver.resolve(now: now, events: [], todos: [], records: records, calendar: calendar)

        XCTAssertEqual(state.hero, .calm)
        guard case .records(let review) = state.review else {
            return XCTFail("Expected records review slot for calm hero")
        }
        XCTAssertEqual(review, records)
    }

    // MARK: - actionableTodoCount

    func testActionableTodoCountReflectsIsActionableNow() {
        let overdue = makeTodo(content: "Overdue", dueDate: now.addingTimeInterval(-3600))
        let today = makeTodo(content: "Today", dueDate: now)
        let noDueDate = makeTodo(content: "NoDueDate")
        let farFuture = makeTodo(content: "Far", dueDate: now.addingTimeInterval(60 * 60 * 24 * 30))
        let completed = makeTodo(content: "Completed", isCompleted: true)

        let state = resolver.resolve(
            now: now,
            events: [],
            todos: [overdue, today, noDueDate, farFuture, completed],
            records: [],
            calendar: calendar
        )

        XCTAssertEqual(state.actionableTodoCount, 3)
    }

    // MARK: - "Today" event filtering

    func testEventsOutsideTodayAreIgnoredForActiveAndImminentSelection() {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let futureImminentLookingEvent = makeEvent(
            title: "Tomorrow",
            start: tomorrow.addingTimeInterval(600),
            end: tomorrow.addingTimeInterval(1800)
        )

        let state = resolver.resolve(now: now, events: [futureImminentLookingEvent], todos: [], records: [], calendar: calendar)

        XCTAssertEqual(state.hero, .calm)
        XCTAssertTrue(state.urgentEvents.isEmpty)
    }
}
