import Combine
import Foundation
import UIKit

@MainActor
final class NotieeStore: ObservableObject {
    @Published internal(set) var events: [ScheduledEvent]
    @Published internal(set) var allEvents: [ScheduledEvent]
    @Published internal(set) var todos: [NoteTodo]
    @Published internal(set) var records: [NoteRecord]
    @Published internal(set) var customFolders: [CustomFolder]
    @Published internal(set) var customTags: [EventTag]
    @Published internal(set) var eventTagMapping: [String: UUID]
    @Published internal(set) var lastPersistenceError: String?

    @Published var currentDate: Date
    private var timerCancellable: AnyCancellable?

    internal let calendar: Calendar
    internal let recordStore: NoteRecordPersisting
    internal let folderStore: CustomFolderPersisting
    internal let tagStore: EventTagPersisting
    internal let eventStore: ScheduledEventPersisting
    internal let scheduleMatcher: ScheduleMatcher
    internal let aiService: any AIProcessingService
    internal let autoProcess: Bool
    let settingsStore: AppSettingsPersisting

    internal var customEvents: [ScheduledEvent] = []
    internal var calendarEvents: [ScheduledEvent] = []

    @Published internal(set) var ignoredCalendarEventKeys: Set<String> = []
    @Published internal(set) var liveActivityDisabledEventIDs: Set<UUID> = []

    var aiEnabled: Bool {
        settingsStore.loadBool(forKey: UDK.aiEnabled, defaultValue: true)
    }

    var autoProcessAfterCapture: Bool {
        settingsStore.loadBool(forKey: UDK.autoProcessAfterCapture, defaultValue: true)
    }

    var semesterStartDate: Date? {
        guard let timeInterval = UserDefaults.standard.object(forKey: UDK.semesterStartDate) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: timeInterval)
    }

    var showWeekNumbers: Bool {
        if UserDefaults.standard.object(forKey: UDK.showWeekNumbers) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: UDK.showWeekNumbers)
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
        customEvents: [ScheduledEvent] = [],
        todos: [NoteTodo] = [],
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

        if let data = UserDefaults.standard.data(forKey: UDK.ignoredCalendarEventKeys),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.ignoredCalendarEventKeys = decoded
        }

        if let data = UserDefaults.standard.data(forKey: UDK.liveActivityDisabledEventIDs),
           let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            self.liveActivityDisabledEventIDs = decoded
        }

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

    func totalTokens(in range: TimeRange, includeDeleted: Bool) -> Int {
        if includeDeleted {
            return records(in: range).reduce(0) { $0 + $1.tokenUsage }
                + deletedRecords(in: range).reduce(0) { $0 + $1.tokenUsage }
        }
        return totalTokens(in: range)
    }

    func allRecords(in range: TimeRange, includeDeleted: Bool) -> [NoteRecord] {
        if includeDeleted {
            return records(in: range) + deletedRecords(in: range)
        }
        return records(in: range)
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
        let matchedEvents = events.filter { eventIDs.contains($0.id) && !CalendarService.shared.isHolidayEvent($0) }

        var seenTitles: Set<String> = []
        var deduped: [ScheduledEvent] = []
        for event in matchedEvents {
            let normalizedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !seenTitles.contains(normalizedTitle) {
                seenTitles.insert(normalizedTitle)
                deduped.append(event)
            }
        }
        return deduped
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
                || record.detailedContent.localizedCaseInsensitiveContains(normalizedQuery)
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
        let recordJSONStore = JSONNoteRecordStore.live
        let folderJSONStore = JSONCustomFolderStore.live
        let tagJSONStore = JSONEventTagStore.live
        let eventJSONStore = JSONScheduledEventStore.live

        let persistedRecords = (try? recordJSONStore.loadRecords()) ?? []
        let persistedFolders = (try? folderJSONStore.loadFolders()) ?? []
        let persistedTags = (try? tagJSONStore.loadTags()) ?? []

        let customTags = persistedTags.filter { !$0.name.hasPrefix("mapping_") }
        var mapping: [String: UUID] = [:]
        for tag in persistedTags where tag.name.hasPrefix("mapping_") {
            let title = String(tag.name.dropFirst("mapping_".count))
            if let tagID = UUID(uuidString: tag.colorHex) {
                mapping[title] = tagID
            }
        }

        let finalTags = EventTag.systemTags + customTags
        let customEvents = (try? eventJSONStore.loadEvents()) ?? []

        return NotieeStore(
            currentDate: currentDate,
            events: [],
            customEvents: customEvents,
            todos: [],
            records: persistedRecords,
            customFolders: persistedFolders,
            customTags: finalTags,
            eventTagMapping: mapping,
            recordStore: recordJSONStore,
            folderStore: folderJSONStore,
            tagStore: tagJSONStore,
            eventStore: eventJSONStore,
            settingsStore: settingsStore,
            autoProcess: true
        )
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
