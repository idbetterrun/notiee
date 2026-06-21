import Combine
import Foundation
import UIKit

@MainActor
final class CalendarManager: ObservableObject {
    @Published var events: [ScheduledEvent]
    @Published var allEvents: [ScheduledEvent]
    @Published var currentDate: Date
    @Published var ignoredCalendarEventKeys: Set<String>
    @Published var liveActivityDisabledEventIDs: Set<UUID>

    let calendar: Calendar
    let scheduleMatcher: ScheduleMatcher
    let eventStore: ScheduledEventPersisting
    var persistedRecordsProvider: () -> [NoteRecord]

    internal var customEvents: [ScheduledEvent]
    internal var calendarEvents: [ScheduledEvent] = []

    private static let recordTitleSuffix = " 拍记"

    private var timerCancellable: AnyCancellable?

    init(
        currentDate: Date = Date(),
        calendar: Calendar = .current,
        customEvents: [ScheduledEvent],
        eventStore: ScheduledEventPersisting,
        scheduleMatcher: ScheduleMatcher = ScheduleMatcher(),
        persistedRecordsProvider: @escaping () -> [NoteRecord] = { [] }
    ) {
        self.currentDate = currentDate
        self.calendar = calendar
        self.customEvents = customEvents
        self.eventStore = eventStore
        self.scheduleMatcher = scheduleMatcher
        self.persistedRecordsProvider = persistedRecordsProvider
        self.events = []
        self.allEvents = []

        if let data = UserDefaults.standard.data(forKey: UDK.ignoredCalendarEventKeys),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            self.ignoredCalendarEventKeys = decoded
        } else {
            self.ignoredCalendarEventKeys = []
        }

        if let data = UserDefaults.standard.data(forKey: UDK.liveActivityDisabledEventIDs),
           let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            self.liveActivityDisabledEventIDs = decoded
        } else {
            self.liveActivityDisabledEventIDs = []
        }

        Task { await updateLiveActivity() }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LiveActivitySettingsChanged"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.updateLiveActivity() }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.currentDate = Date()
                await self?.updateLiveActivity()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.objectWillChange.send()
        }

        setupTimeRefresh()
        updateEventsList()
    }

    // MARK: - Time Refresh

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

    // MARK: - Computed Properties

    var currentEvent: ScheduledEvent? {
        scheduleMatcher.currentEvent(from: events, at: currentDate)
    }

    var eventsWithRecords: [ScheduledEvent] {
        let records = persistedRecordsProvider().filter { !$0.isDeleted }
        let recordsWithEventID = records.filter { $0.eventID != nil }
        let directEventIDs = Set(recordsWithEventID.compactMap { $0.eventID })

        // Tier 1: UUID直接匹配
        var matchedByID = events.filter { directEventIDs.contains($0.id) && !CalendarService.shared.isHolidayEvent($0) }
        var matchedIDs = Set(matchedByID.map { $0.id })

        // Orphan records: UUID匹配失败的记录
        let orphans = recordsWithEventID.filter { record in
            guard let eid = record.eventID else { return false }
            return !matchedIDs.contains(eid)
        }

        // Tier 2: Date proximity — record.capturedAt 落在 event 时间窗口内 且 标题匹配
        var tier2MatchedRecordIDs = Set<UUID>()
        for record in orphans {
            let recordTitle = record.title.replacingOccurrences(of: Self.recordTitleSuffix, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !recordTitle.isEmpty else { continue }
            if let match = events.first(where: { event in
                !matchedIDs.contains(event.id)
                && event.contains(record.capturedAt)
                && event.title == recordTitle
                && !CalendarService.shared.isHolidayEvent(event)
            }) {
                matchedByID.append(match)
                matchedIDs.insert(match.id)
                tier2MatchedRecordIDs.insert(record.id)
            }
        }

        // Tier 3: Title-only match 作为最后回退
        let tier3Orphans = orphans.filter { !tier2MatchedRecordIDs.contains($0.id) }
        let orphanEventTitles = Set(tier3Orphans.map {
            $0.title.replacingOccurrences(of: Self.recordTitleSuffix, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })
        let matchedByTitle = events.filter { event in
            !matchedIDs.contains(event.id)
            && orphanEventTitles.contains(event.title)
            && !CalendarService.shared.isHolidayEvent(event)
        }

        matchedByID.append(contentsOf: matchedByTitle)

        // Dedup by event ID (not title)
        var seenIDs: Set<UUID> = []
        var deduped: [ScheduledEvent] = []
        for event in matchedByID {
            if !seenIDs.contains(event.id) {
                seenIDs.insert(event.id)
                deduped.append(event)
            }
        }
        return deduped
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

    func eventTitle(for record: NoteRecord) -> String? {
        guard let eventID = record.eventID else {
            return nil
        }
        // Tier 1: UUID直接匹配
        if let match = events.first(where: { $0.id == eventID && !CalendarService.shared.isHolidayEvent($0) }) {
            return match.title
        }
        // Tier 2: Date proximity + 标题匹配
        let recordTitle = record.title.replacingOccurrences(of: Self.recordTitleSuffix, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recordTitle.isEmpty else { return nil }
        if let match = events.first(where: { $0.contains(record.capturedAt) && $0.title == recordTitle && !CalendarService.shared.isHolidayEvent($0) }) {
            return match.title
        }
        // Tier 3: Title-only match 作为最后回退
        return events.first { $0.title == recordTitle && !CalendarService.shared.isHolidayEvent($0) }?.title
    }

    // MARK: - Event Mutations

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

    /// 仅能修改本地 customEvents（.notiee/.ai/.ics）。系统日历事件不在 customEvents，返回 false。
    @discardableResult
    func updateEvent(id: UUID, title: String?, startDate: Date?, endDate: Date?, notes: String?) -> Bool {
        guard let idx = customEvents.firstIndex(where: { $0.id == id }) else { return false }
        if let title { customEvents[idx].title = title }
        if let startDate { customEvents[idx].startDate = startDate }
        if let endDate { customEvents[idx].endDate = endDate }
        if let notes { customEvents[idx].notes = notes }
        customEvents[idx].updatedAt = Date()
        persistCustomEvents()
        updateEventsList()
        return true
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

    func isEventIgnored(_ event: ScheduledEvent) -> Bool {
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

    /// Clears tagID on all events that reference the given tag.
    func clearTagReferences(for tagID: UUID) {
        for i in 0..<events.count {
            if events[i].tagID == tagID {
                events[i].tagID = nil
            }
        }
    }

    func updateEventTag(eventID: UUID, tagID: UUID?) {
        if let index = events.firstIndex(where: { $0.id == eventID }) {
            events[index].tagID = tagID
        }
    }

    // MARK: - Calendar Sync

    func syncCalendar(eventTagMapping: [String: UUID]) {
        Task {
            let granted = await CalendarService.shared.requestAccess()
            if granted {
                let fetchedEvents = CalendarService.shared.fetchEvents(currentDate: currentDate)
                await MainActor.run {
                    self.calendarEvents = fetchedEvents.map { event in
                        var newEvent = event
                        newEvent.tagID = eventTagMapping[event.title]
                        return newEvent
                    }
                    self.updateEventsList()
                }
            }
        }
    }

    // MARK: - Live Activity

    func updateLiveActivity() async {
        let isEnabled = UserDefaults.standard.bool(forKey: UDK.liveActivityEnabled)
        guard isEnabled else {
            LiveActivityManager.shared.endActivity()
            return
        }

        let checkDate = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ? currentDate : Date()

        if let event = scheduleMatcher.currentEvent(from: events, at: checkDate) {
            guard !event.isAllDay else {
                LiveActivityManager.shared.endActivity()
                return
            }
            guard !liveActivityDisabledEventIDs.contains(event.id) else {
                LiveActivityManager.shared.endActivity()
                return
            }
            LiveActivityManager.shared.startActivity(for: event)
        } else {
            LiveActivityManager.shared.endActivity()
        }
    }

    func toggleLiveActivityForEvent(_ eventID: UUID) {
        if liveActivityDisabledEventIDs.contains(eventID) {
            liveActivityDisabledEventIDs.remove(eventID)
        } else {
            liveActivityDisabledEventIDs.insert(eventID)
            LiveActivityManager.shared.endActivity()
        }
        if let data = try? JSONEncoder().encode(liveActivityDisabledEventIDs) {
            UserDefaults.standard.set(data, forKey: UDK.liveActivityDisabledEventIDs)
        }
        Task { await updateLiveActivity() }
    }

    // MARK: - Internal Helpers

    func updateEventsList() {
        let all = (customEvents + calendarEvents).sorted { $0.startDate < $1.startDate }
        self.allEvents = all
        self.events = all.filter { !isEventIgnored($0) }

        let advanceTime = UserDefaults.standard.integer(forKey: UDK.notificationAdvanceTime)
        NotificationManager.shared.scheduleNotifications(for: self.events, advanceTimeMinutes: advanceTime)
        Task { await updateLiveActivity() }
    }

    func persistCustomEvents() {
        try? eventStore.saveEvents(customEvents)
    }

    func persistIgnoredKeys() {
        if let data = try? JSONEncoder().encode(ignoredCalendarEventKeys) {
            UserDefaults.standard.set(data, forKey: UDK.ignoredCalendarEventKeys)
        }
    }
}
