import Combine
import Foundation

@MainActor
final class NotieeStore: ObservableObject {
    @Published private(set) var events: [ScheduledEvent]
    @Published private(set) var todos: [NoteTodo]
    @Published private(set) var records: [NoteRecord]
    @Published private(set) var lastPersistenceError: String?

    let currentDate: Date

    private let calendar: Calendar
    private let recordStore: NoteRecordPersisting
    private let scheduleMatcher: ScheduleMatcher

    init(
        currentDate: Date = Date(),
        calendar: Calendar = .current,
        events: [ScheduledEvent],
        todos: [NoteTodo],
        records: [NoteRecord],
        recordStore: NoteRecordPersisting = JSONNoteRecordStore.live,
        scheduleMatcher: ScheduleMatcher = ScheduleMatcher()
    ) {
        self.currentDate = currentDate
        self.calendar = calendar
        self.events = events
        self.todos = todos
        self.records = records
        self.recordStore = recordStore
        self.scheduleMatcher = scheduleMatcher
    }

    var currentEvent: ScheduledEvent? {
        scheduleMatcher.currentEvent(from: events, at: currentDate)
    }

    var sortedRecords: [NoteRecord] {
        records.sorted { lhs, rhs in
            lhs.capturedAt > rhs.capturedAt
        }
    }

    var uncategorizedCount: Int {
        records.filter { $0.eventID == nil }.count
    }

    var todayRecordCount: Int {
        records.filter { calendar.isDate($0.capturedAt, inSameDayAs: currentDate) }.count
    }

    var pendingRecordsCount: Int {
        records.filter { $0.processingState == .pending }.count
    }

    func records(matching query: String) -> [NoteRecord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return sortedRecords
        }

        return sortedRecords.filter { record in
            record.title.localizedCaseInsensitiveContains(normalizedQuery)
                || record.summary.localizedCaseInsensitiveContains(normalizedQuery)
                || record.ocrText.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    func eventTitle(for record: NoteRecord) -> String? {
        guard let eventID = record.eventID else {
            return nil
        }

        return events.first { $0.id == eventID }?.title
    }

    func todos(for record: NoteRecord) -> [NoteTodo] {
        todos
            .filter { $0.recordID == record.id }
            .sorted { lhs, rhs in
                lhs.createdAt < rhs.createdAt
            }
    }

    @discardableResult
    func capturePhoto(localImagePath: String? = nil) -> NoteRecord {
        let event = currentEvent
        let captureIndex = records.count + 1
        let record = NoteRecord(
            eventID: event?.id,
            capturedAt: currentDate,
            localImagePath: localImagePath ?? "mock://capture-\(captureIndex)",
            title: event.map { "\($0.title) 拍记" } ?? "未分类拍记",
            processingState: .pending
        )

        records.insert(record, at: 0)
        persistRecords()
        return record
    }

    static func sample(currentDate: Date = Date()) -> NotieeStore {
        let today = TodayViewModel.sample(currentDate: currentDate)
        return NotieeStore(
            currentDate: currentDate,
            events: today.events,
            todos: today.todos,
            records: today.records
        )
    }

    static func live(currentDate: Date = Date()) -> NotieeStore {
        let today = TodayViewModel.sample(currentDate: currentDate)
        let store = JSONNoteRecordStore.live
        let persistedRecords = (try? store.loadRecords()) ?? []

        return NotieeStore(
            currentDate: currentDate,
            events: today.events,
            todos: today.todos,
            records: persistedRecords.isEmpty ? today.records : persistedRecords,
            recordStore: store
        )
    }

    private func persistRecords() {
        do {
            try recordStore.saveRecords(records)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }
}
