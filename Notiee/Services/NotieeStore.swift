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
    private let aiService: MockAIProcessingService
    private let autoProcess: Bool

    init(
        currentDate: Date = Date(),
        calendar: Calendar = .current,
        events: [ScheduledEvent],
        todos: [NoteTodo],
        records: [NoteRecord],
        recordStore: NoteRecordPersisting = JSONNoteRecordStore.live,
        scheduleMatcher: ScheduleMatcher = ScheduleMatcher(),
        aiService: MockAIProcessingService = MockAIProcessingService(),
        autoProcess: Bool = false
    ) {
        self.currentDate = currentDate
        self.calendar = calendar
        self.events = events
        self.todos = todos
        self.records = records
        self.recordStore = recordStore
        self.scheduleMatcher = scheduleMatcher
        self.aiService = aiService
        self.autoProcess = autoProcess
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

        if autoProcess {
            enqueueProcessing(for: record)
        }

        return record
    }

    /// 手动触发对指定记录的 AI 处理管线。
    func processRecord(_ record: NoteRecord) {
        enqueueProcessing(for: record)
    }

    // MARK: - Record & Todo Mutations

    func updateRecord(_ updated: NoteRecord) {
        guard let index = records.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        records[index] = updated
        persistRecords()
    }

    func addTodo(_ todo: NoteTodo) {
        todos.append(todo)
    }

    func toggleTodo(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }
        todos[index].isCompleted.toggle()
    }

    // MARK: - AI Processing Pipeline

    private func enqueueProcessing(for record: NoteRecord) {
        let recordID = record.id
        let eventTitle = eventTitle(for: record)
        let service = aiService

        Task {
            // Phase 1: pending → processing（模拟网络传输延迟）
            try? await Task.sleep(for: .milliseconds(Int.random(in: 800...1500)))
            self.setProcessingState(.processing, for: recordID)

            // Phase 2: processing → completed（模拟大模型推理耗时）
            let delayMs = Int(Double.random(in: service.processingDelay) * 1000)
            try? await Task.sleep(for: .milliseconds(delayMs))

            let result = service.generate(for: eventTitle)
            self.applyAIResult(result, to: recordID)
        }
    }

    private func setProcessingState(_ state: AIProcessingState, for recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else {
            return
        }
        records[index].processingState = state
        persistRecords()
    }

    private func applyAIResult(_ result: MockAIProcessingService.Result, to recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else {
            return
        }
        records[index].title = result.title
        records[index].ocrText = result.ocrText
        records[index].summary = result.summary
        records[index].processingState = .completed
        persistRecords()

        for content in result.todos {
            let todo = NoteTodo(recordID: recordID, content: content)
            addTodo(todo)
        }
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
            recordStore: store,
            autoProcess: true
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
