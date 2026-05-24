import Combine
import Foundation
import UIKit

@MainActor
final class NotieeStore: ObservableObject {
    @Published private(set) var events: [ScheduledEvent]
    @Published private(set) var allEvents: [ScheduledEvent]
    @Published private(set) var todos: [NoteTodo]
    @Published private(set) var records: [NoteRecord]
    @Published private(set) var customFolders: [CustomFolder]
    @Published private(set) var customTags: [EventTag]
    @Published private(set) var eventTagMapping: [String: UUID] // eventTitle -> tagID
    @Published private(set) var lastPersistenceError: String?

    @Published var currentDate: Date
    private var timerCancellable: AnyCancellable?

    private let calendar: Calendar
    private let recordStore: NoteRecordPersisting
    private let folderStore: CustomFolderPersisting
    private let tagStore: EventTagPersisting
    private let eventStore: ScheduledEventPersisting
    private let scheduleMatcher: ScheduleMatcher
    private let aiService: any AIProcessingService
    private let autoProcess: Bool
    let settingsStore: AppSettingsPersisting

    private var customEvents: [ScheduledEvent] = []
    private var calendarEvents: [ScheduledEvent] = []

    // Map of identifier to ignore mode: "once_\(date)" or "future"
    @Published private(set) var ignoredCalendarEventKeys: Set<String> = []

    var aiEnabled: Bool {
        settingsStore.loadBool(forKey: "notiee.aiEnabled", defaultValue: true)
    }

    var autoProcessAfterCapture: Bool {
        settingsStore.loadBool(forKey: "notiee.autoProcessAfterCapture", defaultValue: true)
    }

    var semesterStartDate: Date? {
        guard let timeInterval = UserDefaults.standard.object(forKey: "notiee.semesterStartDate") as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: timeInterval)
    }

    var showWeekNumbers: Bool {
        if UserDefaults.standard.object(forKey: "notiee.showWeekNumbers") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "notiee.showWeekNumbers")
    }

    func formattedDateWithWeek(for date: Date) -> String {
        let dateString = date.formatted(.dateTime.year().month(.defaultDigits).day().locale(Locale(identifier: "zh_CN")))
        if showWeekNumbers {
            if let semesterStart = semesterStartDate {
                let daysSinceStart = calendar.dateComponents([.day], from: semesterStart, to: date).day ?? 0
                let weekNumber = max(1, (daysSinceStart / 7) + 1)
                return "\(dateString) 第\(weekNumber)周"
            } else {
                let weekOfYear = calendar.component(.weekOfYear, from: date)
                return "\(dateString) 第\(weekOfYear)周"
            }
        }
        return dateString
    }

    init(
        currentDate: Date = Date(),
        calendar: Calendar = .current,
        events: [ScheduledEvent] = [],
        customEvents: [ScheduledEvent],
        todos: [NoteTodo],
        records: [NoteRecord],
        customFolders: [CustomFolder] = [],
        customTags: [EventTag] = EventTag.systemTags,
        eventTagMapping: [String: UUID] = [:],
        recordStore: NoteRecordPersisting = JSONNoteRecordStore.live,
        folderStore: CustomFolderPersisting = JSONCustomFolderStore.live,
        tagStore: EventTagPersisting = JSONEventTagStore.live,
        eventStore: ScheduledEventPersisting = JSONScheduledEventStore.live,
        scheduleMatcher: ScheduleMatcher = ScheduleMatcher(),
        aiService: any AIProcessingService = RealAIProcessingService(),
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live,
        autoProcess: Bool = false
    ) {
        self.currentDate = currentDate
        self.calendar = calendar
        self.events = events
        self.allEvents = events
        self.customEvents = customEvents
        self.todos = todos
        self.records = records
        self.customFolders = customFolders
        self.customTags = customTags
        self.eventTagMapping = eventTagMapping
        self.recordStore = recordStore
        self.folderStore = folderStore
        self.tagStore = tagStore
        self.eventStore = eventStore
        self.scheduleMatcher = scheduleMatcher
        self.aiService = aiService
        self.settingsStore = settingsStore
        self.autoProcess = autoProcess
        
        if let data = UserDefaults.standard.data(forKey: "notiee.ignoredCalendarEventKeys"),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.ignoredCalendarEventKeys = decoded
        }
        
        // Listen to Live Activity setting changes if needed, or update immediately
        Task { await updateLiveActivity() }
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("LiveActivitySettingsChanged"), object: nil, queue: .main) { [weak self] _ in
            Task { await self?.updateLiveActivity() }
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.currentDate = Date()
                await self?.updateLiveActivity()
            }
        }
        
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.objectWillChange.send()
        }
        
        setupTimeRefresh()
        updateEventsList()
    }
    
    private func setupTimeRefresh() {
        // Only run timer if not in a test environment, or if we want real-time updates.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        
        timerCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshTimeState()
            }
    }
    
    private func refreshTimeState() {
        self.currentDate = Date()
        Task { await updateLiveActivity() }
    }

    var currentEvent: ScheduledEvent? {
        scheduleMatcher.currentEvent(from: events, at: currentDate)
    }

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

    var todayRecordCount: Int {
        todayRecords.count
    }
    
    var todayRecords: [NoteRecord] {
        sortedRecords.filter { calendar.isDate($0.capturedAt, inSameDayAs: currentDate) }
    }
    
    func records(in range: TimeRange) -> [NoteRecord] {
        let now = Date()
        return sortedRecords.filter { record in
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
    
    func totalTokens(in range: TimeRange) -> Int {
        records(in: range).reduce(0) { $0 + $1.tokenUsage }
    }
    
    func deletedRecords(in range: TimeRange) -> [NoteRecord] {
        let now = Date()
        return deletedRecords.filter { record in
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
    
    func deletedTokens(in range: TimeRange) -> Int {
        deletedRecords(in: range).reduce(0) { $0 + $1.tokenUsage }
    }
    
    func topRecordsByToken(in range: TimeRange, limit: Int = 5) -> [NoteRecord] {
        Array(records(in: range).sorted(by: { $0.tokenUsage > $1.tokenUsage }).prefix(limit))
    }

    var pendingRecordsCount: Int {
        sortedRecords.filter { $0.processingState == .pending }.count
    }

    var eventsWithRecords: [ScheduledEvent] {
        let eventIDs = Set(sortedRecords.compactMap { $0.eventID })
        return events.filter { eventIDs.contains($0.id) }
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
    func capturePhoto(localImagePaths: [String]? = nil, eventID: UUID? = nil) -> NoteRecord {
        let resolvedEventID = eventID ?? currentEvent?.id
        let resolvedEventTitle: String? = {
            if let id = resolvedEventID {
                return events.first(where: { $0.id == id })?.title
            }
            return currentEvent?.title
        }()

        let record = NoteRecord(
            eventID: resolvedEventID,
            capturedAt: currentDate,
            localImagePaths: localImagePaths ?? [],
            title: resolvedEventTitle.map { "\($0) 拍记" } ?? "未分类拍记",
            processingState: .pending
        )

        records.insert(record, at: 0)
        persistRecords()

        if autoProcess && aiEnabled && autoProcessAfterCapture {
            enqueueProcessing(for: record)
        }

        return record
    }

    func processRecord(_ record: NoteRecord) {
        guard aiEnabled else { return }
        enqueueProcessing(for: record)
    }

    // MARK: - Record & Todo Mutations

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
        records[index].isDeleted.toggle()
        persistRecords()
    }
    
    func permanentlyDelete(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        
        // delete local images
        for path in record.localImagePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
        
        // delete associated todos
        todos.removeAll { $0.recordID == id }
        
        records.remove(at: index)
        persistRecords()
    }
    
    func toggleDeletedMultiple(ids: Set<UUID>, isDeleted: Bool) {
        for id in ids {
            if let index = records.firstIndex(where: { $0.id == id }) {
                records[index].isDeleted = isDeleted
            }
        }
        persistRecords()
    }
    
    func permanentlyDeleteMultiple(ids: Set<UUID>) {
        records.removeAll { record in
            if ids.contains(record.id) {
                for path in record.localImagePaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
                // delete associated todos
                todos.removeAll { $0.recordID == record.id }
                return true
            }
            return false
        }
        persistRecords()
    }

    func addTodo(_ todo: NoteTodo) {
        todos.append(todo)
    }

    func replaceTodos(for recordID: UUID, with newTodos: [NoteTodo]) {
        todos.removeAll { $0.recordID == recordID }
        todos.append(contentsOf: newTodos)
    }

    func deleteTodo(id: UUID) {
        todos.removeAll { $0.id == id }
    }

    func toggleTodo(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }
        todos[index].isCompleted.toggle()
        persistRecords()
    }

    func updateTodoContent(id: UUID, newContent: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }
        todos[index].content = newContent
        persistRecords()
    }
    
    // MARK: - Custom Folders
    
    func createFolder(name: String) {
        let folder = CustomFolder(name: name)
        customFolders.append(folder)
        persistFolders()
    }

    func renameFolder(id: UUID, newName: String) {
        if let index = customFolders.firstIndex(where: { $0.id == id }) {
            customFolders[index].name = newName
            persistFolders()
        }
    }

    func deleteFolder(id: UUID) {
        customFolders.removeAll { $0.id == id }
        for i in 0..<records.count {
            if records[i].folderID == id {
                records[i].folderID = nil
            }
        }
        persistFolders()
        persistRecords()
    }
    
    func assignRecordToFolder(recordID: UUID, folderID: UUID?) {
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index].folderID = folderID
            persistRecords()
        }
    }
    
    // MARK: - Event Tags
    
    func createTag(name: String, colorHex: String) {
        let tag = EventTag(name: name, colorHex: colorHex, isSystem: false)
        customTags.append(tag)
        persistTags()
    }
    
    func updateTag(id: UUID, name: String, colorHex: String) {
        if let index = customTags.firstIndex(where: { $0.id == id && !$0.isSystem }) {
            customTags[index].name = name
            customTags[index].colorHex = colorHex
            persistTags()
        }
    }
    
    func deleteTag(id: UUID) {
        customTags.removeAll { $0.id == id && !$0.isSystem }
        // Remove mappings
        let keysToRemove = eventTagMapping.filter { $0.value == id }.map { $0.key }
        for key in keysToRemove {
            eventTagMapping.removeValue(forKey: key)
        }
        for i in 0..<events.count {
            if events[i].tagID == id {
                events[i].tagID = nil
            }
        }
        persistTags()
    }
    
    func getOrCreateImportedFolder() -> UUID {
        if let folder = customFolders.first(where: { $0.name == "已导入" }) {
            return folder.id
        }
        let newFolder = CustomFolder(name: "已导入")
        customFolders.append(newFolder)
        persistFolders()
        return newFolder.id
    }
    
    func assignTagToEvent(eventID: UUID, tagID: UUID?) {
        if let index = events.firstIndex(where: { $0.id == eventID }) {
            events[index].tagID = tagID
            let title = events[index].title
            if let tagID = tagID {
                eventTagMapping[title] = tagID
            } else {
                eventTagMapping.removeValue(forKey: title)
            }
            persistTags()
        }
    }

    func addEvent(_ event: ScheduledEvent) {
        customEvents.append(event)
        persistCustomEvents()
        updateEventsList()
    }

    func deleteEvent(id: UUID) {
        customEvents.removeAll { $0.id == id }
        persistCustomEvents()
        updateEventsList()
    }

    func ignoreCalendarEvent(identifier: String, date: Date, future: Bool) {
        if future {
            ignoredCalendarEventKeys.insert("future_\(identifier)")
        } else {
            let dateStr = date.formatted(.dateTime.year().month().day())
            ignoredCalendarEventKeys.insert("once_\(identifier)_\(dateStr)")
        }
        persistIgnoredKeys()
        updateEventsList()
    }

    func restoreCalendarEvent(identifier: String) {
        ignoredCalendarEventKeys = ignoredCalendarEventKeys.filter { !$0.contains(identifier) }
        persistIgnoredKeys()
        updateEventsList()
    }

    private func persistIgnoredKeys() {
        if let data = try? JSONEncoder().encode(ignoredCalendarEventKeys) {
            UserDefaults.standard.set(data, forKey: "notiee.ignoredCalendarEventKeys")
        }
    }

    private func isEventIgnored(_ event: ScheduledEvent) -> Bool {
        if case .systemCalendar(let identifier) = event.source {
            if ignoredCalendarEventKeys.contains("future_\(identifier)") {
                return true
            }
            let dateStr = event.startDate.formatted(.dateTime.year().month().day())
            if ignoredCalendarEventKeys.contains("once_\(identifier)_\(dateStr)") {
                return true
            }
        }
        return false
    }

    private func updateEventsList() {
        let all = (customEvents + calendarEvents).sorted { $0.startDate < $1.startDate }
        self.allEvents = all
        self.events = all.filter { !isEventIgnored($0) }
        
        let advanceTime = UserDefaults.standard.integer(forKey: "notiee.notificationAdvanceTime")
        NotificationManager.shared.scheduleNotifications(for: self.events, advanceTimeMinutes: advanceTime)
        Task { await updateLiveActivity() }
    }

    func addStandaloneTodo(content: String, dueDate: Date?, hasReminder: Bool) {
        let todo = NoteTodo(recordID: nil, content: content, dueDate: dueDate, hasReminder: hasReminder)
        todos.append(todo)
    }

    // MARK: - Calendar Sync

    func syncCalendar() {
        Task {
            let granted = await CalendarService.shared.requestAccess()
            if granted {
                let fetchedEvents = CalendarService.shared.fetchEvents(currentDate: currentDate)
                await MainActor.run {
                    self.calendarEvents = fetchedEvents.map { event in
                        var newEvent = event
                        newEvent.tagID = self.eventTagMapping[event.title]
                        return newEvent
                    }
                    self.updateEventsList()
                }
            }
        }
    }
    
    // MARK: - Live Activity
    
    func updateLiveActivity() async {
        let isEnabled = UserDefaults.standard.bool(forKey: "notiee.liveActivityEnabled")
        guard isEnabled else {
            LiveActivityManager.shared.endActivity()
            return
        }
        
        // Use Date() for real-time check, or currentDate for tests
        let checkDate = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ? currentDate : Date()
        
        if let event = scheduleMatcher.currentEvent(from: events, at: checkDate) {
            LiveActivityManager.shared.startActivity(for: event)
        } else {
            LiveActivityManager.shared.endActivity()
        }
    }

    // MARK: - AI Processing Pipeline

    func retryAIProcessing(for recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        var record = records[index]
        guard record.processingState == .failed else { return }
        
        record.processingState = .pending
        records[index] = record
        persistRecords()
        
        enqueueProcessing(for: record)
    }

    func updateRecordEvent(recordID: UUID, newEventID: UUID?) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].eventID = newEventID
        persistRecords()
    }

    private func enqueueProcessing(for record: NoteRecord) {
        guard aiEnabled else { return }
        let recordID = record.id
        let service = aiService

        Task {
            await MainActor.run { self.setProcessingState(.processing, for: recordID) }

            do {
                let eventTitle = self.events.first(where: { $0.id == record.eventID })?.title
                let result = try await service.process(imagePaths: record.localImagePaths, eventTitle: eventTitle)
                
                await MainActor.run { self.applyAIResult(result, to: recordID) }
            } catch {
                await MainActor.run {
                    self.setProcessingState(.failed, for: recordID)
                    print("AI Processing failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func setProcessingState(_ state: AIProcessingState, for recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else {
            return
        }
        records[index].processingState = state
        persistRecords()
    }

    private func applyAIResult(_ result: AIProcessingResult, to recordID: UUID) {
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index].title = result.title
            records[index].ocrText = result.ocrText
            records[index].summary = result.summary
            records[index].detailedContent = result.detailedContent
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

    static func sample(currentDate: Date = Date()) -> NotieeStore {
        let today = TodayViewModel.sample(currentDate: currentDate)
        return NotieeStore(
            currentDate: currentDate,
            events: today.events,
            customEvents: today.events,
            todos: today.todos,
            records: today.records,
            customFolders: []
        )
    }

    static func live(currentDate: Date = Date(), settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) -> NotieeStore {
        let store = JSONNoteRecordStore.live
        let folderStore = JSONCustomFolderStore.live
        let tagStore = JSONEventTagStore.live
        let eventStore = JSONScheduledEventStore.live
        
        let persistedRecords = (try? store.loadRecords()) ?? []
        let persistedFolders = (try? folderStore.loadFolders()) ?? []
        let persistedTags = (try? tagStore.loadTags()) ?? []
        
        let customTags = persistedTags.filter { !$0.name.hasPrefix("mapping_") }
        var mapping: [String: UUID] = [:]
        for tag in persistedTags where tag.name.hasPrefix("mapping_") {
            let title = String(tag.name.dropFirst("mapping_".count))
            if let tagID = UUID(uuidString: tag.colorHex) {
                mapping[title] = tagID
            }
        }
        
        let finalTags = EventTag.systemTags + customTags

        let customEvents = (try? eventStore.loadEvents()) ?? []

        return NotieeStore(
            currentDate: currentDate,
            events: [],
            customEvents: customEvents,
            todos: [],
            records: persistedRecords,
            customFolders: persistedFolders,
            customTags: finalTags,
            eventTagMapping: mapping,
            recordStore: store,
            folderStore: folderStore,
            tagStore: tagStore,
            eventStore: eventStore,
            settingsStore: settingsStore,
            autoProcess: true
        )
    }

    private func persistCustomEvents() {
        try? eventStore.saveEvents(customEvents)
    }

    private func persistRecords() {
        do {
            try recordStore.saveRecords(records)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }
    
    private func persistFolders() {
        try? folderStore.saveFolders(customFolders)
    }
    
    private func persistTags() {
        // Encode mappings as fake tags to save in the same store
        let mappingTags = eventTagMapping.map { key, value in
            EventTag(id: UUID(), name: "mapping_\(key)", colorHex: value.uuidString, isSystem: true)
        }
        let tagsToSave = customTags.filter { !$0.isSystem } + mappingTags
        try? tagStore.saveTags(tagsToSave)
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case today = "今日"
    case last7Days = "近七天"
    case thisMonth = "本月"
    case halfYear = "半年"
    case oneYear = "一年"
    var id: String { self.rawValue }
}

import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestPermission() async -> Bool {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            return try await UNUserNotificationCenter.current().requestAuthorization(options: options)
        } catch {
            print("Failed to request notification permission: \(error)")
            return false
        }
    }
    
    func scheduleNotifications(for events: [ScheduledEvent], advanceTimeMinutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests() // Reset all notifications
        
        guard UserDefaults.standard.bool(forKey: "notiee.notificationEnabled") else { return }
        
        for event in events {
            guard event.startDate > Date() else { continue } // Only upcoming
            
            let triggerDate = event.startDate.addingTimeInterval(-Double(advanceTimeMinutes * 60))
            guard triggerDate > Date() else { continue }
            
            let content = UNMutableNotificationContent()
            content.title = "日程提醒"
            if advanceTimeMinutes == 0 {
                content.body = "您的日程「\(event.title)」马上开始！"
            } else {
                content.body = "您的日程「\(event.title)」将在 \(advanceTimeMinutes) 分钟后开始。"
            }
            content.sound = .default
            
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let request = UNNotificationRequest(identifier: event.id.uuidString, content: content, trigger: trigger)
            
            center.add(request) { error in
                if let error = error {
                    print("Error scheduling notification: \(error)")
                }
            }
        }
    }
}
