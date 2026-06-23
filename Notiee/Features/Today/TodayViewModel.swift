import Combine
import Foundation

@MainActor
final class TodayViewModel: ObservableObject {

    @Published var currentDate: Date
    private let calendar: Calendar
    private let scheduleMatcher: ScheduleMatcher
    weak var store: NotieeStore?

    @Published private(set) var events: [ScheduledEvent]
    @Published private(set) var todos: [NoteTodo]
    @Published private(set) var records: [NoteRecord]
    private var cancellables: Set<AnyCancellable> = []

    /// Standalone initializer for tests and previews.
    init(
        currentDate: Date = Date(),
        calendar: Calendar = .current,
        events: [ScheduledEvent],
        todos: [NoteTodo],
        records: [NoteRecord],
        scheduleMatcher: ScheduleMatcher = ScheduleMatcher()
    ) {
        self.currentDate = currentDate
        self.calendar = calendar
        self.events = events
        self.todos = todos
        self.records = records
        self.scheduleMatcher = scheduleMatcher
        self.store = nil
    }

    /// Store-backed initializer — data is kept in sync with the shared NotieeStore.
    init(store: NotieeStore) {
        self.currentDate = store.currentDate
        self.calendar = .current
        self.events = store.events
        self.todos = store.todos
        self.records = store.records
        self.scheduleMatcher = ScheduleMatcher()
        self.store = store

        store.$events.assign(to: &$events)
        store.$todos.assign(to: &$todos)
        store.$records.assign(to: &$records)
        store.$currentDate.assign(to: &$currentDate)
        store.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    // MARK: - Current Event
    
    private var todayEvents: [ScheduledEvent] {
        events.filter {
            calendar.isDate($0.startDate, inSameDayAs: currentDate) ||
            calendar.isDate($0.endDate, inSameDayAs: currentDate) ||
            ($0.startDate < currentDate && $0.endDate > currentDate)
        }
    }

    var currentEvent: ScheduledEvent? {
        scheduleMatcher.currentEvent(from: todayEvents, at: currentDate)
    }

    // MARK: - Grouped Timeline

    var completedEvents: [ScheduledEvent] {
        todayEvents
            .filter { $0.status(at: currentDate) == .completed }
            .sorted { $0.startDate < $1.startDate }
    }

    var currentEvents: [ScheduledEvent] {
        todayEvents
            .filter { $0.status(at: currentDate) == .current }
            .sorted { $0.startDate < $1.startDate }
    }

    var upcomingEvents: [ScheduledEvent] {
        todayEvents
            .filter { $0.status(at: currentDate) == .upcoming }
            .sorted { $0.startDate < $1.startDate }
    }

    var timelineItems: [ScheduledEvent] {
        todayEvents.sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Todos

    var pendingTodos: [NoteTodo] {
        todos
            .filter { !$0.isCompleted }
            .filter(isVisible)
            .sorted { $0.createdAt < $1.createdAt }
    }

    var allTodos: [NoteTodo] {
        todos
            .filter(isVisible)
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// 待办是否应在 Today 展示。
    /// - 无关联拍记的独立待办（如 Spark / 手动创建）：始终展示。
    /// - 有关联拍记的待办：仅当其拍记仍存在且未删除时展示。
    private func isVisible(_ todo: NoteTodo) -> Bool {
        guard let recordID = todo.recordID else { return true }
        guard let record = store?.sortedRecords.first(where: { $0.id == recordID }) else { return false }
        return !record.isDeleted
    }

    func toggleTodo(id: UUID) {
        store?.toggleTodo(id: id)
    }

    func editTodo(id: UUID, newContent: String) {
        store?.updateTodoContent(id: id, newContent: newContent)
    }

    func record(for todo: NoteTodo) -> NoteRecord? {
        guard let store = store else { return nil }
        return store.records.first(where: { $0.id == todo.recordID })
    }

    // MARK: - Today Records

    var todayRecords: [NoteRecord] {
        records
            .filter { !$0.isDeleted && calendar.isDate($0.capturedAt, inSameDayAs: currentDate) }
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    // MARK: - Formatted Date

    var formattedDateWithWeek: String {
        let weekday = currentDate.formatted(
            .dateTime.weekday(.abbreviated)
                .locale(Locale(identifier: "zh_CN"))
        )
        if let store = store {
            return "\(store.formattedDateWithWeek(for: currentDate)) \(weekday)"
        }
        
        let monthDay = currentDate.formatted(
            .dateTime.month(.defaultDigits).day()
                .locale(Locale(identifier: "zh_CN"))
        )
        let currentWeekday = currentDate.formatted(
            .dateTime.weekday(.abbreviated)
                .locale(Locale(identifier: "zh_CN"))
        )
        let weekOfYear = calendar.component(.weekOfYear, from: currentDate)
        let weekStr = " 第\(weekOfYear)周"
        return "\(monthDay)日 \(currentWeekday)\(weekStr)"
    }

    // MARK: - Sample Data

    static func sample(currentDate: Date = Date()) -> TodayViewModel {
        let calendar = Calendar.current
        let currentStart = calendar.date(byAdding: .minute, value: -35, to: currentDate)!
        let currentEnd = calendar.date(byAdding: .minute, value: 55, to: currentDate)!
        let earlierStart = calendar.date(byAdding: .hour, value: -3, to: currentDate)!
        let earlierEnd = calendar.date(byAdding: .hour, value: -2, to: currentDate)!
        let upcomingStart = calendar.date(byAdding: .hour, value: 2, to: currentDate)!
        let upcomingEnd = calendar.date(byAdding: .hour, value: 3, to: currentDate)!

        let course = ScheduledEvent(
            title: "当前课程",
            startDate: currentStart,
            endDate: currentEnd,
            kind: .course,
            updatedAt: calendar.date(byAdding: .hour, value: -1, to: currentDate)!,
            isAllDay: false
        )

        let events = [
            ScheduledEvent(
                title: "已完成课程",
                startDate: earlierStart,
                endDate: earlierEnd,
                kind: .course,
                updatedAt: earlierStart,
                isAllDay: false
            ),
            course,
            ScheduledEvent(
                title: "即将开始的会议",
                startDate: upcomingStart,
                endDate: upcomingEnd,
                kind: .meeting,
                updatedAt: upcomingStart,
                isAllDay: false
            )
        ]

        let todos = [
            NoteTodo(
                recordID: nil,
                content: "整理课堂笔记",
                createdAt: calendar.date(byAdding: .minute, value: -20, to: currentDate)!
            ),
            NoteTodo(
                recordID: nil,
                content: "完成课后练习",
                createdAt: calendar.date(byAdding: .minute, value: -12, to: currentDate)!
            ),
            NoteTodo(
                recordID: nil,
                content: "复习上次课程内容",
                isCompleted: true,
                createdAt: calendar.date(byAdding: .hour, value: -2, to: currentDate)!
            )
        ]

        return TodayViewModel(
            currentDate: currentDate,
            calendar: calendar,
            events: events,
            todos: todos,
            records: []
        )
    }
}
