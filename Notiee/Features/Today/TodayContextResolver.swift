import Foundation

/// Deterministic, local hero selection for the Today 2.0 Context Dashboard.
///
/// `resolve` is a pure function: same inputs always produce the same
/// `TodayDashboardState`. No network calls, no side effects, no dependency on
/// wall-clock time other than the `now` parameter passed in by the caller.
struct TodayContextResolver {
    /// A todo counts as due-soon (Hero priority 2) when it is overdue, or due at or
    /// before `now + dueSoonInterval`.
    static let dueSoonInterval: TimeInterval = 2 * 60 * 60
    /// An event counts as imminent (Hero priority 3) when it starts after `now` and at
    /// or before `now + imminentEventInterval`.
    static let imminentEventInterval: TimeInterval = 30 * 60

    /// Hero priority 4: the minimum number of today's records that trigger record momentum.
    private static let recordMomentumThreshold = 3
    private static let urgentCap = 2
    private static let reviewCap = 3

    func resolve(
        now: Date,
        events: [ScheduledEvent],
        todos: [NoteTodo],
        records: [NoteRecord],
        calendar: Calendar
    ) -> TodayDashboardState {
        let todayEvents = events.filter { isToday($0, now: now, calendar: calendar) }
        let incompleteTodos = todos.filter { !$0.isCompleted }
        let todayRecords = records
            .filter { !$0.isDeleted && calendar.isDate($0.capturedAt, inSameDayAs: now) }
            .sorted { $0.capturedAt > $1.capturedAt }

        let activeEvents = todayEvents
            .filter { $0.status(at: now) == .current }
            .sorted { $0.startDate < $1.startDate }

        let dueTodos = incompleteTodos
            .filter { todo in
                guard let due = todo.dueDate else { return false }
                return due <= now.addingTimeInterval(Self.dueSoonInterval)
            }
            .sorted { $0.dueDate! < $1.dueDate! }

        let imminentEvents = todayEvents
            .filter { now < $0.startDate && $0.startDate <= now.addingTimeInterval(Self.imminentEventInterval) }
            .sorted { $0.startDate < $1.startDate }

        let hero = resolveHero(
            activeEvents: activeEvents,
            dueTodos: dueTodos,
            imminentEvents: imminentEvents,
            todayRecordCount: todayRecords.count
        )

        let urgentTodos = dueTodos
            .filter { $0.id != heroTodoID(hero) }
            .prefix(Self.urgentCap)
            .map { $0 }

        let urgentEvents = imminentEvents
            .filter { $0.id != heroEventID(hero) }
            .prefix(Self.urgentCap)
            .map { $0 }

        let review = resolveReview(
            hero: hero,
            incompleteTodos: incompleteTodos,
            todayRecords: todayRecords,
            now: now,
            calendar: calendar
        )

        let actionableTodoCount = incompleteTodos
            .filter { TodoBucketer.isActionableNow($0, now: now, calendar: calendar) }
            .count

        return TodayDashboardState(
            hero: hero,
            urgentTodos: urgentTodos,
            urgentEvents: urgentEvents,
            review: review,
            todayRecordCount: todayRecords.count,
            actionableTodoCount: actionableTodoCount
        )
    }

    // MARK: - Hero

    private func resolveHero(
        activeEvents: [ScheduledEvent],
        dueTodos: [NoteTodo],
        imminentEvents: [ScheduledEvent],
        todayRecordCount: Int
    ) -> TodayHero {
        if let active = activeEvents.first {
            return .activeEvent(active)
        }
        if let due = dueTodos.first {
            return .dueTodo(due)
        }
        if let imminent = imminentEvents.first {
            return .imminentEvent(imminent)
        }
        if todayRecordCount >= Self.recordMomentumThreshold {
            return .recordMomentum(count: todayRecordCount)
        }
        return .calm
    }

    private func heroTodoID(_ hero: TodayHero) -> UUID? {
        if case .dueTodo(let todo) = hero { return todo.id }
        return nil
    }

    private func heroEventID(_ hero: TodayHero) -> UUID? {
        if case .imminentEvent(let event) = hero { return event.id }
        return nil
    }

    // MARK: - Review

    private func resolveReview(
        hero: TodayHero,
        incompleteTodos: [NoteTodo],
        todayRecords: [NoteRecord],
        now: Date,
        calendar: Calendar
    ) -> TodayReviewSlot {
        switch hero {
        case .activeEvent, .dueTodo, .imminentEvent:
            let excludedID = heroTodoID(hero)
            let actionable = incompleteTodos
                .filter { $0.id != excludedID }
                .filter { TodoBucketer.isActionableNow($0, now: now, calendar: calendar) }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                .prefix(Self.reviewCap)
                .map { $0 }
            return .todos(actionable)
        case .recordMomentum, .calm:
            return .records(Array(todayRecords.prefix(Self.reviewCap)))
        }
    }

    // MARK: - Helpers

    private func isToday(_ event: ScheduledEvent, now: Date, calendar: Calendar) -> Bool {
        calendar.isDate(event.startDate, inSameDayAs: now) ||
        calendar.isDate(event.endDate, inSameDayAs: now) ||
        (event.startDate < now && event.endDate > now)
    }
}
