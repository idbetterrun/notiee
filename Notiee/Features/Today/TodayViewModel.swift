import Combine
import Foundation

@MainActor
final class TodayViewModel: ObservableObject {

    let currentDate: Date
    private let calendar: Calendar
    private let scheduleMatcher: ScheduleMatcher
    private var cancellables: Set<AnyCancellable> = []

    // When backed by a shared NotieeStore, data flows from the store.
    // When standalone (e.g. tests), data is held locally.
    @Published private(set) var events: [ScheduledEvent]
    @Published private(set) var todos: [NoteTodo]
    @Published private(set) var records: [NoteRecord]

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
    }

    /// Store-backed initializer — data is kept in sync with the shared NotieeStore.
    init(store: NotieeStore) {
        self.currentDate = store.currentDate
        self.calendar = .current
        self.events = store.events
        self.todos = store.todos
        self.records = store.records
        self.scheduleMatcher = ScheduleMatcher()

        store.$events
            .assign(to: &$events)
        store.$todos
            .assign(to: &$todos)
        store.$records
            .assign(to: &$records)
    }

    var currentEvent: ScheduledEvent? {
        scheduleMatcher.currentEvent(from: events, at: currentDate)
    }

    var timelineItems: [ScheduledEvent] {
        events.sorted { lhs, rhs in
            lhs.startDate < rhs.startDate
        }
    }

    var pendingTodos: [NoteTodo] {
        todos
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                lhs.createdAt < rhs.createdAt
            }
    }

    var todayRecords: [NoteRecord] {
        records
            .filter { calendar.isDate($0.capturedAt, inSameDayAs: currentDate) }
            .sorted { lhs, rhs in
                lhs.capturedAt > rhs.capturedAt
            }
    }

    static func sample(currentDate: Date = Date()) -> TodayViewModel {
        let calendar = Calendar.current
        let currentStart = calendar.date(byAdding: .minute, value: -35, to: currentDate)!
        let currentEnd = calendar.date(byAdding: .minute, value: 55, to: currentDate)!
        let earlierStart = calendar.date(byAdding: .hour, value: -3, to: currentDate)!
        let earlierEnd = calendar.date(byAdding: .hour, value: -2, to: currentDate)!
        let upcomingStart = calendar.date(byAdding: .hour, value: 2, to: currentDate)!
        let upcomingEnd = calendar.date(byAdding: .hour, value: 3, to: currentDate)!

        let course = ScheduledEvent(
            title: "产品设计课",
            startDate: currentStart,
            endDate: currentEnd,
            kind: .course,
            updatedAt: calendar.date(byAdding: .hour, value: -1, to: currentDate)!
        )

        let events = [
            ScheduledEvent(
                title: "高等数学",
                startDate: earlierStart,
                endDate: earlierEnd,
                kind: .course,
                updatedAt: earlierStart
            ),
            course,
            ScheduledEvent(
                title: "项目讨论",
                startDate: upcomingStart,
                endDate: upcomingEnd,
                kind: .meeting,
                updatedAt: upcomingStart
            )
        ]

        let todos = [
            NoteTodo(
                recordID: nil,
                content: "整理白板上的用户旅程图",
                createdAt: calendar.date(byAdding: .minute, value: -20, to: currentDate)!
            ),
            NoteTodo(
                recordID: nil,
                content: "补充竞品截图到课程记录",
                createdAt: calendar.date(byAdding: .minute, value: -12, to: currentDate)!
            ),
            NoteTodo(
                recordID: nil,
                content: "同步昨天的课堂笔记",
                isCompleted: true,
                createdAt: calendar.date(byAdding: .hour, value: -2, to: currentDate)!
            )
        ]

        let records = [
            NoteRecord(
                eventID: course.id,
                capturedAt: calendar.date(byAdding: .minute, value: -8, to: currentDate)!,
                localImagePath: "mock://whiteboard-flow",
                title: "白板：拍记流程",
                ocrText: "capture queue, schedule matching, ai summary",
                summary: "拍照后自动关联当前课程，进入后台处理队列。",
                processingState: .completed
            ),
            NoteRecord(
                eventID: course.id,
                capturedAt: calendar.date(byAdding: .minute, value: -46, to: currentDate)!,
                localImagePath: "mock://schedule-context",
                title: "课件：日程感知",
                ocrText: "calendar import, current event, inbox fallback",
                summary: "通过日程时间段给照片补充课程上下文。",
                processingState: .processing
            ),
            NoteRecord(
                eventID: nil,
                capturedAt: calendar.date(byAdding: .day, value: -1, to: currentDate)!,
                localImagePath: "mock://yesterday",
                title: "昨天记录",
                ocrText: "",
                summary: "",
                processingState: .completed
            )
        ]

        return TodayViewModel(
            currentDate: currentDate,
            calendar: calendar,
            events: events,
            todos: todos,
            records: records
        )
    }
}
