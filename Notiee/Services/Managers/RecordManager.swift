import Combine
import Foundation

@MainActor
final class RecordManager: ObservableObject {
    @Published var records: [NoteRecord]
    @Published var todos: [NoteTodo]
    @Published var lastPersistenceError: String?

    var onRecordsDeleted: (([UUID]) -> Void)?

    let recordStore: NoteRecordPersisting
    let todoStore: NoteTodoPersisting
    let calendar: Calendar

    init(
        records: [NoteRecord],
        todos: [NoteTodo],
        recordStore: NoteRecordPersisting,
        todoStore: NoteTodoPersisting = JSONNoteTodoStore.live,
        calendar: Calendar = .current
    ) {
        self.records = records
        self.todos = todos
        self.recordStore = recordStore
        self.todoStore = todoStore
        self.calendar = calendar
    }

    // MARK: - Record Queries

    var sortedRecords: [NoteRecord] {
        records.filter { !$0.isDeleted }.sorted { lhs, rhs in
            lhs.capturedAt > rhs.capturedAt
        }
    }

    var favoriteRecords: [NoteRecord] {
        sortedRecords.filter { $0.isFavorite }
    }

    var deletedRecords: [NoteRecord] {
        records.filter { $0.isDeleted }.sorted { lhs, rhs in
            lhs.capturedAt > rhs.capturedAt
        }
    }

    var uncategorizedCount: Int {
        sortedRecords.filter { $0.eventID == nil }.count
    }

    var pendingRecordsCount: Int {
        sortedRecords.filter { $0.processingState == .pending }.count
    }

    func todayRecords(relativeTo currentDate: Date) -> [NoteRecord] {
        sortedRecords.filter { calendar.isDate($0.capturedAt, inSameDayAs: currentDate) }
    }

    func todayRecordCount(relativeTo currentDate: Date) -> Int {
        todayRecords(relativeTo: currentDate).count
    }

    func records(in range: TimeRange, relativeTo now: Date = Date()) -> [NoteRecord] {
        sortedRecords.filter { record in
            switch range {
            case .today:
                return calendar.isDate(record.capturedAt, inSameDayAs: now)
            case .last7Days:
                guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return false }
                return record.capturedAt >= sevenDaysAgo
            case .thisMonth:
                return calendar.isDate(record.capturedAt, equalTo: now, toGranularity: .month)
            case .halfYear:
                guard let halfYearAgo = calendar.date(byAdding: .month, value: -6, to: now) else { return false }
                return record.capturedAt >= halfYearAgo
            case .oneYear:
                guard let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) else { return false }
                return record.capturedAt >= oneYearAgo
            }
        }
    }

    func totalTokens(in range: TimeRange, relativeTo now: Date = Date()) -> Int {
        records(in: range, relativeTo: now).reduce(0) { $0 + $1.tokenUsage }
    }

    func totalTokens(in range: TimeRange, includeDeleted: Bool, relativeTo now: Date = Date()) -> Int {
        if includeDeleted {
            return records(in: range, relativeTo: now).reduce(0) { $0 + $1.tokenUsage }
                + deletedRecords(in: range, relativeTo: now).reduce(0) { $0 + $1.tokenUsage }
        }
        return totalTokens(in: range, relativeTo: now)
    }

    func allRecords(in range: TimeRange, includeDeleted: Bool, relativeTo now: Date = Date()) -> [NoteRecord] {
        if includeDeleted {
            return records(in: range, relativeTo: now) + deletedRecords(in: range, relativeTo: now)
        }
        return records(in: range, relativeTo: now)
    }

    func deletedRecords(in range: TimeRange, relativeTo now: Date = Date()) -> [NoteRecord] {
        deletedRecords.filter { record in
            switch range {
            case .today:
                return calendar.isDate(record.capturedAt, inSameDayAs: now)
            case .last7Days:
                guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return false }
                return record.capturedAt >= sevenDaysAgo
            case .thisMonth:
                return calendar.isDate(record.capturedAt, equalTo: now, toGranularity: .month)
            case .halfYear:
                guard let halfYearAgo = calendar.date(byAdding: .month, value: -6, to: now) else { return false }
                return record.capturedAt >= halfYearAgo
            case .oneYear:
                guard let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) else { return false }
                return record.capturedAt >= oneYearAgo
            }
        }
    }

    func deletedTokens(in range: TimeRange, relativeTo now: Date = Date()) -> Int {
        deletedRecords(in: range, relativeTo: now).reduce(0) { $0 + $1.tokenUsage }
    }

    func topRecordsByToken(in range: TimeRange, limit: Int = 5, relativeTo now: Date = Date()) -> [NoteRecord] {
        Array(records(in: range, relativeTo: now).sorted(by: { $0.tokenUsage > $1.tokenUsage }).prefix(limit))
    }

    func records(matching query: String) -> [NoteRecord] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return sortedRecords
        }
        return sortedRecords.filter { record in
            guard !record.isEncrypted else { return false }
            return record.title.localizedCaseInsensitiveContains(normalizedQuery)
                || record.summary.localizedCaseInsensitiveContains(normalizedQuery)
                || record.ocrText.localizedCaseInsensitiveContains(normalizedQuery)
                || record.detailedContent.localizedCaseInsensitiveContains(normalizedQuery)
        }
    }

    // MARK: - Record Mutations

    func capturePhoto(localImagePaths: [String]? = nil, eventID: UUID? = nil, eventTitle: String? = nil, capturedAt: Date) -> NoteRecord {
        let title = eventTitle.map { "\($0) 拍记" } ?? "未分类拍记"
        let record = NoteRecord(
            eventID: eventID,
            capturedAt: capturedAt,
            localImagePaths: localImagePaths ?? [],
            title: title,
            processingState: .pending
        )
        records.insert(record, at: 0)
        persistRecords()
        return record
    }

    func addRecord(_ record: NoteRecord) {
        records.insert(record, at: 0)
        persistRecords()
    }

    func updateRecord(_ updated: NoteRecord) {
        guard let index = records.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        records[index] = updated
        persistRecords()
    }

    func toggleFavorite(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            return
        }
        records[index].isFavorite.toggle()
        persistRecords()
    }

    func toggleDeleted(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let becomingDeleted = !records[index].isDeleted
        records[index].isDeleted.toggle()
        if becomingDeleted {
            accumulateDeletedTokens(records[index].tokenUsage)
        }
        persistRecords()
    }

    func permanentlyDelete(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        if !record.isDeleted {
            accumulateDeletedTokens(record.tokenUsage)
        }

        for path in record.localImagePaths {
            LocalImageStore.deleteImage(path: path)
        }
        if record.isEncrypted {
            SecureRecordCodec(crypto: CryptoService.shared()).deleteBlob(for: id)
        }

        todos.removeAll { $0.recordID == id }

        records.remove(at: index)
        persistRecords()
        persistTodos()
        onRecordsDeleted?([id])
    }

    func toggleDeletedMultiple(ids: Set<UUID>, isDeleted: Bool) {
        for id in ids {
            if let index = records.firstIndex(where: { $0.id == id }) {
                let wasDeleted = records[index].isDeleted
                records[index].isDeleted = isDeleted
                if isDeleted && !wasDeleted {
                    accumulateDeletedTokens(records[index].tokenUsage)
                }
            }
        }
        persistRecords()
    }

    func permanentlyDeleteMultiple(ids: Set<UUID>) {
        var deletedIDs: [UUID] = []
        records.removeAll { record in
            if ids.contains(record.id) {
                if !record.isDeleted {
                    accumulateDeletedTokens(record.tokenUsage)
                }
                for path in record.localImagePaths {
                    LocalImageStore.deleteImage(path: path)
                }
                if record.isEncrypted {
                    SecureRecordCodec(crypto: CryptoService.shared()).deleteBlob(for: record.id)
                }
                todos.removeAll { $0.recordID == record.id }
                deletedIDs.append(record.id)
                return true
            }
            return false
        }
        persistRecords()
        persistTodos()
        onRecordsDeleted?(deletedIDs)
    }

    func updateRecordEvent(recordID: UUID, newEventID: UUID?) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].eventID = newEventID
        persistRecords()
    }

    func assignRecordToFolder(recordID: UUID, folderID: UUID?) {
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index].folderID = folderID
            persistRecords()
        }
    }

    func clearFolderReferences(for folderID: UUID) {
        for i in 0..<records.count {
            if records[i].folderID == folderID {
                records[i].folderID = nil
            }
        }
        persistRecords()
    }

    // MARK: - Todo Mutations

    func todos(for record: NoteRecord) -> [NoteTodo] {
        todos
            .filter { $0.recordID == record.id }
            .sorted { lhs, rhs in
                lhs.createdAt < rhs.createdAt
            }
    }

    func addTodo(_ todo: NoteTodo) {
        todos.append(todo)
        persistTodos()
    }

    func replaceTodos(for recordID: UUID, with newTodos: [NoteTodo]) {
        todos.removeAll { $0.recordID == recordID }
        todos.append(contentsOf: newTodos)
        persistTodos()
    }

    func deleteTodo(id: UUID) {
        todos.removeAll { $0.id == id }
        persistTodos()
    }

    func toggleTodo(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }
        todos[index].isCompleted.toggle()
        persistTodos()
    }

    func updateTodoContent(id: UUID, newContent: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }
        todos[index].content = newContent
        persistTodos()
    }

    func addStandaloneTodo(content: String, dueDate: Date?, hasReminder: Bool) {
        let todo = NoteTodo(recordID: nil, content: content, dueDate: dueDate, hasReminder: hasReminder)
        todos.append(todo)
        persistTodos()
    }

    // MARK: - Persistence

    func persistRecords() {
        do {
            try recordStore.saveRecords(records)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    func persistTodos() {
        do {
            try todoStore.saveTodos(todos)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

    // MARK: - Private

    private func accumulateDeletedTokens(_ tokens: Int) {
        let current = UserDefaults.standard.integer(forKey: UDK.accumulatedDeletedTokens)
        UserDefaults.standard.set(current + tokens, forKey: UDK.accumulatedDeletedTokens)
    }
}

// MARK: - AIPipeline Support

extension RecordManager {
    func record(id: UUID) -> NoteRecord? {
        records.first { $0.id == id }
    }

    func setProcessingState(_ state: AIProcessingState, for recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else {
            return
        }
        records[index].processingState = state
        persistRecords()
    }

    func incrementRetryCount(for recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].aiRetryCount += 1
        persistRecords()
    }

    func applyAIResult(_ result: AIProcessingResult, to recordID: UUID) {
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index].title = result.title
            records[index].ocrText = result.ocrText
            records[index].summary = result.summary
            records[index].detailedContent = result.detailedContent
            records[index].keyPoints = result.keyPoints
            records[index].definitions = result.definitions
            records[index].modelsUsed = result.modelsUsed
            records[index].tokenUsage = result.tokenUsage
            records[index].processingState = .completed

            persistRecords()

            for content in result.todos {
                let todo = NoteTodo(recordID: recordID, content: content)
                addTodo(todo)
            }
        }
    }
}
