import Combine
import Foundation
import UIKit

@MainActor
final class NotieeStore: ObservableObject {
    // MARK: - @Published Properties (mirrored from Managers via Combine)

    @Published var events: [ScheduledEvent] = []
    @Published var allEvents: [ScheduledEvent] = []
    @Published var todos: [NoteTodo] = []
    @Published var records: [NoteRecord] = []
    @Published var customFolders: [CustomFolder] = []
    @Published var customTags: [EventTag] = []
    @Published var eventTagMapping: [String: UUID] = [:]
    @Published var lastPersistenceError: String?
    @Published var currentDate: Date
    @Published var ignoredCalendarEventKeys: Set<String> = []
    @Published var liveActivityDisabledEventIDs: Set<UUID> = []

    // MARK: - Managers

    let recordManager: RecordManager
    let calendarManager: CalendarManager
    let folderTagManager: FolderTagManager
    let aiPipelineManager: AIPipelineManager

    let settingsStore: AppSettingsPersisting
    let autoProcess: Bool
    let calendar: Calendar

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initializer (Manager-based, used by live())

    init(
        recordManager: RecordManager,
        calendarManager: CalendarManager,
        folderTagManager: FolderTagManager,
        aiPipelineManager: AIPipelineManager,
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live,
        autoProcess: Bool = false,
        calendar: Calendar = .current
    ) {
        self.recordManager = recordManager
        self.calendarManager = calendarManager
        self.folderTagManager = folderTagManager
        self.aiPipelineManager = aiPipelineManager
        self.settingsStore = settingsStore
        self.autoProcess = autoProcess
        self.calendar = calendar

        // Set initial values from Managers
        self.currentDate = calendarManager.currentDate
        self.records = recordManager.records
        self.todos = recordManager.todos
        self.lastPersistenceError = recordManager.lastPersistenceError
        self.events = calendarManager.events
        self.allEvents = calendarManager.allEvents
        self.ignoredCalendarEventKeys = calendarManager.ignoredCalendarEventKeys
        self.liveActivityDisabledEventIDs = calendarManager.liveActivityDisabledEventIDs
        self.customFolders = folderTagManager.customFolders
        self.customTags = folderTagManager.customTags
        self.eventTagMapping = folderTagManager.eventTagMapping

        setupSubscriptions()

        // Wire pipeline record access to self
        aiPipelineManager.recordAccess = self
    }

    // MARK: - Backward-compatible Convenience Init

    convenience init(
        currentDate: Date = Date(),
        calendar: Calendar = .current,
        events: [ScheduledEvent] = [],
        customEvents: [ScheduledEvent] = [],
        todos: [NoteTodo] = [],
        records: [NoteRecord],
        customFolders: [CustomFolder] = [],
        customTags: [EventTag] = EventTag.systemTags,
        eventTagMapping: [String: UUID] = [:],
        recordStore: NoteRecordPersisting = JSONNoteRecordStore.live,
        todoStore: NoteTodoPersisting = JSONNoteTodoStore.live,
        folderStore: CustomFolderPersisting = JSONCustomFolderStore.live,
        tagStore: EventTagPersisting = JSONEventTagStore.live,
        eventStore: ScheduledEventPersisting = JSONScheduledEventStore.live,
        scheduleMatcher: ScheduleMatcher = ScheduleMatcher(),
        aiService: any AIProcessingService = AIProcessingServiceFactory.makeDefault(),
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live,
        autoProcess: Bool = false,
        notifier: (any ProcessingResultNotifying)? = nil
    ) {
        let recordMgr = RecordManager(
            records: records,
            todos: todos,
            recordStore: recordStore,
            todoStore: todoStore,
            calendar: calendar
        )
        let folderTagMgr = FolderTagManager(
            customFolders: customFolders,
            customTags: customTags,
            eventTagMapping: eventTagMapping,
            folderStore: folderStore,
            tagStore: tagStore
        )
        let aiPipelineMgr = AIPipelineManager(
            aiService: aiService,
            settingsStore: settingsStore
        )
        aiPipelineMgr.notifier = notifier
        let calendarMgr = CalendarManager(
            currentDate: currentDate,
            calendar: calendar,
            customEvents: customEvents,
            eventStore: eventStore,
            scheduleMatcher: scheduleMatcher,
            persistedRecordsProvider: { [weak recordMgr] in recordMgr?.records ?? [] }
        )
        self.init(
            recordManager: recordMgr,
            calendarManager: calendarMgr,
            folderTagManager: folderTagMgr,
            aiPipelineManager: aiPipelineMgr,
            settingsStore: settingsStore,
            autoProcess: autoProcess,
            calendar: calendar
        )
    }

    // MARK: - Combine Sync

    private func setupSubscriptions() {
        // RecordManager → Store
        recordManager.$records.sink { [weak self] in self?.records = $0 }.store(in: &cancellables)
        recordManager.$todos.sink { [weak self] in self?.todos = $0 }.store(in: &cancellables)
        recordManager.$lastPersistenceError.sink { [weak self] in self?.lastPersistenceError = $0 }.store(in: &cancellables)
        recordManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        // CalendarManager → Store
        calendarManager.$events.sink { [weak self] in self?.events = $0 }.store(in: &cancellables)
        calendarManager.$allEvents.sink { [weak self] in self?.allEvents = $0 }.store(in: &cancellables)
        calendarManager.$currentDate.sink { [weak self] in self?.currentDate = $0 }.store(in: &cancellables)
        calendarManager.$ignoredCalendarEventKeys.sink { [weak self] in self?.ignoredCalendarEventKeys = $0 }.store(in: &cancellables)
        calendarManager.$liveActivityDisabledEventIDs.sink { [weak self] in self?.liveActivityDisabledEventIDs = $0 }.store(in: &cancellables)
        calendarManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)

        // FolderTagManager → Store
        folderTagManager.$customFolders.sink { [weak self] in self?.customFolders = $0 }.store(in: &cancellables)
        folderTagManager.$customTags.sink { [weak self] in self?.customTags = $0 }.store(in: &cancellables)
        folderTagManager.$eventTagMapping.sink { [weak self] in self?.eventTagMapping = $0 }.store(in: &cancellables)
        folderTagManager.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    // MARK: - Settings Convenience

    var aiEnabled: Bool {
        settingsStore.loadBool(forKey: UDK.aiEnabled, defaultValue: true)
    }

    var autoProcessAfterCapture: Bool {
        settingsStore.loadBool(forKey: UDK.autoProcessAfterCapture, defaultValue: true)
    }

    // MARK: - Record Queries (delegated to RecordManager)

    var sortedRecords: [NoteRecord] { recordManager.sortedRecords }
    var favoriteRecords: [NoteRecord] { recordManager.favoriteRecords }
    var deletedRecords: [NoteRecord] { recordManager.deletedRecords }
    var uncategorizedCount: Int { recordManager.uncategorizedCount }
    var todayRecordCount: Int { recordManager.todayRecordCount(relativeTo: currentDate) }
    var todayRecords: [NoteRecord] { recordManager.todayRecords(relativeTo: currentDate) }
    var pendingRecordsCount: Int { recordManager.pendingRecordsCount }

    func records(in range: TimeRange) -> [NoteRecord] {
        recordManager.records(in: range, relativeTo: currentDate)
    }

    func totalTokens(in range: TimeRange) -> Int {
        recordManager.totalTokens(in: range, relativeTo: currentDate)
    }

    func totalTokens(in range: TimeRange, includeDeleted: Bool) -> Int {
        recordManager.totalTokens(in: range, includeDeleted: includeDeleted, relativeTo: currentDate)
    }

    func allRecords(in range: TimeRange, includeDeleted: Bool) -> [NoteRecord] {
        recordManager.allRecords(in: range, includeDeleted: includeDeleted, relativeTo: currentDate)
    }

    func deletedRecords(in range: TimeRange) -> [NoteRecord] {
        recordManager.deletedRecords(in: range, relativeTo: currentDate)
    }

    func deletedTokens(in range: TimeRange) -> Int {
        recordManager.deletedTokens(in: range, relativeTo: currentDate)
    }

    func topRecordsByToken(in range: TimeRange, limit: Int = 5) -> [NoteRecord] {
        recordManager.topRecordsByToken(in: range, limit: limit, relativeTo: currentDate)
    }

    func records(matching query: String) -> [NoteRecord] {
        recordManager.records(matching: query)
    }

    func todos(for record: NoteRecord) -> [NoteTodo] {
        recordManager.todos(for: record)
    }

    // MARK: - Calendar Queries (delegated to CalendarManager)

    var currentEvent: ScheduledEvent? { calendarManager.currentEvent }
    var semesterStartDate: Date? { calendarManager.semesterStartDate }
    var showWeekNumbers: Bool { calendarManager.showWeekNumbers }
    var eventsWithRecords: [ScheduledEvent] { calendarManager.eventsWithRecords }

    func formattedDateWithWeek(for date: Date) -> String {
        calendarManager.formattedDateWithWeek(for: date)
    }

    func eventTitle(for record: NoteRecord) -> String? {
        calendarManager.eventTitle(for: record)
    }

    // MARK: - Record Mutations (delegated to RecordManager)

    @discardableResult
    func capturePhoto(localImagePaths: [String]? = nil, eventID: UUID? = nil) -> NoteRecord {
        let resolvedEventID = eventID ?? currentEvent?.id
        let resolvedEventTitle: String? = {
            if let id = resolvedEventID {
                return events.first(where: { $0.id == id })?.title
            }
            return currentEvent?.title
        }()

        let record = recordManager.capturePhoto(
            localImagePaths: localImagePaths,
            eventID: resolvedEventID,
            eventTitle: resolvedEventTitle,
            capturedAt: currentDate
        )

        if autoProcess && aiEnabled && autoProcessAfterCapture {
            let title = eventTitle(for: record)
            aiPipelineManager.enqueueProcessing(
                recordID: record.id,
                localImagePaths: record.localImagePaths,
                eventTitle: title
            )
        }

        return record
    }

    func processRecord(_ record: NoteRecord) {
        guard aiEnabled else { return }
        let title = eventTitle(for: record)
        aiPipelineManager.enqueueProcessing(
            recordID: record.id,
            localImagePaths: record.localImagePaths,
            eventTitle: title
        )
    }

    func addRecord(_ record: NoteRecord) { recordManager.addRecord(record) }
    func updateRecord(_ updated: NoteRecord) { recordManager.updateRecord(updated) }
    func toggleFavorite(id: UUID) { recordManager.toggleFavorite(id: id) }
    func toggleDeleted(id: UUID) { recordManager.toggleDeleted(id: id) }
    func permanentlyDelete(id: UUID) { recordManager.permanentlyDelete(id: id) }
    func toggleDeletedMultiple(ids: Set<UUID>, isDeleted: Bool) {
        recordManager.toggleDeletedMultiple(ids: ids, isDeleted: isDeleted)
    }
    func permanentlyDeleteMultiple(ids: Set<UUID>) {
        recordManager.permanentlyDeleteMultiple(ids: ids)
    }

    // MARK: - Todo Mutations

    func addTodo(_ todo: NoteTodo) { recordManager.addTodo(todo) }
    func replaceTodos(for recordID: UUID, with newTodos: [NoteTodo]) {
        recordManager.replaceTodos(for: recordID, with: newTodos)
    }
    func deleteTodo(id: UUID) { recordManager.deleteTodo(id: id) }
    func toggleTodo(id: UUID) { recordManager.toggleTodo(id: id) }
    func updateTodoContent(id: UUID, newContent: String) {
        recordManager.updateTodoContent(id: id, newContent: newContent)
    }
    func addStandaloneTodo(content: String, dueDate: Date?, hasReminder: Bool) {
        recordManager.addStandaloneTodo(content: content, dueDate: dueDate, hasReminder: hasReminder)
    }

    // MARK: - Folder Mutations

    func createFolder(name: String) { folderTagManager.createFolder(name: name) }
    func renameFolder(id: UUID, newName: String) { folderTagManager.renameFolder(id: id, newName: newName) }
    func deleteFolder(id: UUID) {
        folderTagManager.deleteFolder(id: id)
        recordManager.clearFolderReferences(for: id)
    }
    func assignRecordToFolder(recordID: UUID, folderID: UUID?) {
        recordManager.assignRecordToFolder(recordID: recordID, folderID: folderID)
    }
    func createImportedFolder() -> UUID { folderTagManager.createImportedFolder() }

    @discardableResult
    func findOrCreateFolder(named name: String) -> UUID {
        folderTagManager.findOrCreateFolder(named: name)
    }

    var sparkFolder: CustomFolder? {
        customFolders.first { $0.name == FolderTagManager.sparkFolderName }
    }

    // MARK: - Tag Mutations

    func createTag(name: String, colorHex: String) { folderTagManager.createTag(name: name, colorHex: colorHex) }
    func updateTag(id: UUID, name: String, colorHex: String) {
        folderTagManager.updateTag(id: id, name: name, colorHex: colorHex)
    }
    func deleteTag(id: UUID) {
        folderTagManager.deleteTag(id: id)
        calendarManager.clearTagReferences(for: id)
    }
    func assignTagToEvent(eventID: UUID, tagID: UUID?) {
        // Resolve event title for mapping
        if let event = events.first(where: { $0.id == eventID }) {
            folderTagManager.assignTagToEvent(eventTitle: event.title, tagID: tagID)
        }
        calendarManager.updateEventTag(eventID: eventID, tagID: tagID)
    }

    // MARK: - Event Mutations

    func addEvent(_ event: ScheduledEvent) { calendarManager.addEvent(event) }
    func deleteEvent(id: UUID) { calendarManager.deleteEvent(id: id) }
    func ignoreCalendarEvent(identifier: String, date: Date, future: Bool) {
        calendarManager.ignoreCalendarEvent(identifier: identifier, date: date, future: future)
    }
    func restoreCalendarEvent(identifier: String) {
        calendarManager.restoreCalendarEvent(identifier: identifier)
    }

    // MARK: - Calendar Sync & Live Activity

    func syncCalendar() {
        calendarManager.syncCalendar(eventTagMapping: folderTagManager.eventTagMapping)
    }

    func toggleLiveActivityForEvent(_ eventID: UUID) {
        calendarManager.toggleLiveActivityForEvent(eventID)
    }

    // MARK: - AI Pipeline

    func retryAIProcessing(for recordID: UUID) {
        guard let record = recordManager.record(id: recordID),
              record.processingState == .failed || record.processingState == .deadLetter else { return }
        aiPipelineManager.enqueueProcessing(
            recordID: record.id,
            localImagePaths: record.localImagePaths,
            eventTitle: eventTitle(for: record)
        )
    }

    func resumePendingAIProcessing() async {
        await aiPipelineManager.resumePendingProcessing()
    }

    func captureShortcutScreenshot(localImagePath: String) -> NoteRecord {
        let resolvedEventID = currentEvent?.id
        let resolvedEventTitle: String? = {
            if let id = resolvedEventID {
                return events.first(where: { $0.id == id })?.title
            }
            return currentEvent?.title
        }()

        let title = resolvedEventTitle.map { "\($0) 拍记" } ?? "未分类拍记"
        let record = NoteRecord(
            eventID: resolvedEventID,
            localImagePaths: [localImagePath],
            title: title,
            processingState: .pending,
            processingNotificationState: .requested
        )
        recordManager.addRecord(record)
        return record
    }

    func processImportedScreenshot(recordID: UUID) {
        guard let record = recordManager.record(id: recordID) else { return }
        aiPipelineManager.enqueueProcessing(
            recordID: record.id,
            localImagePaths: record.localImagePaths,
            eventTitle: eventTitle(for: record)
        )
    }

    /// 直接 await 处理完成——供 App Intent 的 perform() 调用。
    func processImportedScreenshotAndWait(recordID: UUID) async {
        guard let record = recordManager.record(id: recordID) else { return }
        await aiPipelineManager.processAndWait(
            recordID: record.id,
            localImagePaths: record.localImagePaths,
            eventTitle: eventTitle(for: record)
        )
    }

    func updateRecordEvent(recordID: UUID, newEventID: UUID?) {
        recordManager.updateRecordEvent(recordID: recordID, newEventID: newEventID)
    }

    // MARK: - Encryption

    /// Encrypts a single record in place: writes the ciphertext blob, redacts the
    /// persisted record, and clears its todos from the todo store.
    func encryptRecord(id: UUID) {
        guard let record = records.first(where: { $0.id == id }), !record.isEncrypted else { return }
        let codec = SecureRecordCodec(crypto: CryptoService.shared())
        let recordTodos = todos(for: record)
        do {
            let (redacted, blob) = try codec.encrypt(record: record, todos: recordTodos)
            try codec.writeBlob(blob, for: id)
            replaceTodos(for: id, with: [])
            updateRecord(redacted)
        } catch {
            lastPersistenceError = "加密失败：\(error.localizedDescription)"
        }
    }

    /// Permanently decrypts a record: restores text, todos, and image files; removes the blob.
    func decryptRecord(id: UUID) {
        guard let record = records.first(where: { $0.id == id }), record.isEncrypted else { return }
        let codec = SecureRecordCodec(crypto: CryptoService.shared())
        guard let blob = codec.readBlob(for: id) else {
            lastPersistenceError = "找不到加密数据。"
            return
        }
        do {
            let (restored, restoredTodos) = try codec.decrypt(record: record, blob: blob)
            updateRecord(restored)
            replaceTodos(for: id, with: restoredTodos)
            codec.deleteBlob(for: id)
        } catch {
            lastPersistenceError = "解密失败：\(error.localizedDescription)"
        }
    }

    /// In-memory decrypt for viewing an encrypted record without persisting plaintext.
    func decryptedForViewing(_ record: NoteRecord) -> (record: NoteRecord, todos: [NoteTodo])? {
        guard record.isEncrypted else { return (record, todos(for: record)) }
        let codec = SecureRecordCodec(crypto: CryptoService.shared())
        guard let blob = codec.readBlob(for: record.id),
              let result = try? codec.decryptForViewing(record: record, blob: blob) else { return nil }
        return result
    }

    /// Decrypts all encrypted records (used when disabling the security feature).
    func decryptAllRecords() {
        for record in records where record.isEncrypted {
            decryptRecord(id: record.id)
        }
    }

    // MARK: - Sample / Live

    static func sample(currentDate: Date = Date()) -> NotieeStore {
        let today = TodayViewModel.sample(currentDate: currentDate)
        // 预览/示例数据走唯一的临时文件存储，绝不写入真实的 records.json / todos.json 等。
        let tmp = FileManager.default.temporaryDirectory
        let prefix = "NotieePreview-\(UUID().uuidString)-"
        func tmpURL(_ name: String) -> URL { tmp.appendingPathComponent("\(prefix)\(name)") }
        return NotieeStore(
            currentDate: currentDate,
            events: today.events,
            customEvents: today.events,
            todos: today.todos,
            records: today.records,
            recordStore: JSONNoteRecordStore(fileURL: tmpURL("records.json")),
            todoStore: JSONNoteTodoStore(fileURL: tmpURL("todos.json")),
            folderStore: JSONCustomFolderStore(fileURL: tmpURL("folders.json")),
            tagStore: JSONEventTagStore(fileURL: tmpURL("tags.json")),
            eventStore: JSONScheduledEventStore(fileURL: tmpURL("events.json"))
        )
    }

    static func live(currentDate: Date = Date(), settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) -> NotieeStore {
        let recordJSONStore = JSONNoteRecordStore.live
        let todoJSONStore = JSONNoteTodoStore.live
        let folderJSONStore = JSONCustomFolderStore.live
        let tagJSONStore = JSONEventTagStore.live
        let eventJSONStore = JSONScheduledEventStore.live

        let persistedRecords = PersistenceRecovery.loadOrQuarantine(fileURL: recordJSONStore.fileURL) { try recordJSONStore.loadRecords() } ?? []
        let persistedTodos = PersistenceRecovery.loadOrQuarantine(fileURL: todoJSONStore.fileURL) { try todoJSONStore.loadTodos() } ?? []
        let persistedFolders = PersistenceRecovery.loadOrQuarantine(fileURL: folderJSONStore.fileURL) { try folderJSONStore.loadFolders() } ?? []
        let persistedTags = PersistenceRecovery.loadOrQuarantine(fileURL: tagJSONStore.fileURL) { try tagJSONStore.loadTags() } ?? []

        let customTags = persistedTags.filter { !$0.name.hasPrefix("mapping_") }
        var mapping: [String: UUID] = [:]
        for tag in persistedTags where tag.name.hasPrefix("mapping_") {
            let title = String(tag.name.dropFirst("mapping_".count))
            if let tagID = UUID(uuidString: tag.colorHex) {
                mapping[title] = tagID
            }
        }

        let finalTags = EventTag.systemTags + customTags
        let customEvents = PersistenceRecovery.loadOrQuarantine(fileURL: eventJSONStore.fileURL) { try eventJSONStore.loadEvents() } ?? []

        let recordMgr = RecordManager(
            records: persistedRecords,
            todos: persistedTodos,
            recordStore: recordJSONStore,
            todoStore: todoJSONStore
        )
        recordMgr.onRecordsDeleted = { ids in
            for id in ids {
                EmbeddingIndex.live.remove(id: id)
                EmbeddingIndex.relatedNotes.remove(id: id)
            }
        }
        let folderTagMgr = FolderTagManager(
            customFolders: persistedFolders,
            customTags: finalTags,
            eventTagMapping: mapping,
            folderStore: folderJSONStore,
            tagStore: tagJSONStore
        )
        let aiPipelineMgr = AIPipelineManager(
            aiService: AIProcessingServiceFactory.makeDefault(),
            settingsStore: settingsStore
        )
        aiPipelineMgr.notifier = NotificationManager.shared
        let calendarMgr = CalendarManager(
            currentDate: currentDate,
            calendar: .current,
            customEvents: customEvents,
            eventStore: eventJSONStore,
            persistedRecordsProvider: { [weak recordMgr] in recordMgr?.records ?? [] }
        )

        return NotieeStore(
            recordManager: recordMgr,
            calendarManager: calendarMgr,
            folderTagManager: folderTagMgr,
            aiPipelineManager: aiPipelineMgr,
            settingsStore: settingsStore,
            autoProcess: true
        )
    }
}

// MARK: - AIPipelineRecordAccess

extension NotieeStore: AIPipelineRecordAccess {
    func record(id: UUID) -> NoteRecord? {
        recordManager.record(id: id)
    }

    func setProcessingState(_ state: AIProcessingState, for recordID: UUID) {
        recordManager.setProcessingState(state, for: recordID)
    }

    func incrementRetryCount(for recordID: UUID) {
        recordManager.incrementRetryCount(for: recordID)
    }

    func applyAIResult(_ result: AIProcessingResult, to recordID: UUID) {
        recordManager.applyAIResult(result, to: recordID)
    }

    func persistRecords() {
        recordManager.persistRecords()
    }

    func recordsNeedingAIRecovery() -> [NoteRecord] {
        recordManager.recordsNeedingAIRecovery()
    }

    func setProcessingNotificationState(_ state: ProcessingNotificationState, for recordID: UUID) {
        recordManager.setProcessingNotificationState(state, for: recordID)
    }

    func eventTitle(for recordID: UUID) -> String? {
        guard let record = recordManager.record(id: recordID) else { return nil }
        return eventTitle(for: record)
    }
}

// MARK: - TimeRange (defined alongside Store for backward compatibility)

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "今日"
    case last7Days = "近七天"
    case thisMonth = "本月"
    case halfYear = "半年"
    case oneYear = "一年"
    var id: String { self.rawValue }
}
