import Foundation
import EventKit
import CryptoKit

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    
    private let eventStore = EKEventStore()
    
    @Published private(set) var isAuthorized = false
    @Published private(set) var availableCalendars: [EKCalendar] = []
    
    private init() {
        checkAuthorizationStatus()
    }

    /// 由系统事件的稳定标识 + 起始日期，确定性地派生一个稳定 UUID。
    /// 用于让系统日历事件在多次抓取间保持同一个 id，从而让拍记的 eventID 持续命中。
    /// 重复性事件的不同场次用 startDate 区分。eventIdentifier 缺失时退回随机 UUID。
    nonisolated static func stableEventID(eventIdentifier: String?, startDate: Date) -> UUID {
        guard let eid = eventIdentifier, !eid.isEmpty else { return UUID() }
        let seed = "\(eid)|\(Int(startDate.timeIntervalSinceReferenceDate))"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let b = Array(digest.prefix(16))
        let bytes: uuid_t = (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                             b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
        return UUID(uuid: bytes)
    }

    private func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            isAuthorized = (status == .fullAccess || status == .writeOnly)
        } else {
            isAuthorized = (status == .authorized)
        }
        if isAuthorized {
            reloadCalendars()
        }
    }
    
    func reloadCalendars() {
        availableCalendars = eventStore.calendars(for: .event).sorted { $0.title < $1.title }
    }
    
    func selectedCalendarIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: UDK.selectedCalendarIdentifiers),
              let ids = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return Set(availableCalendars.map { $0.calendarIdentifier })
        }
        return ids
    }
    
    func saveSelectedCalendarIDs(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: UDK.selectedCalendarIdentifiers)
        }
    }
    
    func requestAccess() async -> Bool {
        do {
            var granted = false
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            isAuthorized = granted
            if granted {
                reloadCalendars()
            }
            return granted
        } catch {
            print("Failed to request calendar access: \(error)")
            return false
        }
    }
    
    func fetchEvents(currentDate: Date = Date()) -> [ScheduledEvent] {
        guard isAuthorized else { return [] }
        
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .month, value: -1, to: currentDate),
              let endDate = calendar.date(byAdding: .month, value: 6, to: currentDate) else {
            return []
        }
        
        let allowedIDs = selectedCalendarIDs()
        let filteredCalendars: [EKCalendar]?
        if allowedIDs.isEmpty {
            filteredCalendars = nil
        } else {
            filteredCalendars = availableCalendars.filter { allowedIDs.contains($0.calendarIdentifier) }
        }
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: filteredCalendars)
        let ekEvents = eventStore.events(matching: predicate)
        
        return ekEvents.map { ekEvent in
            // Determine kind based on title keywords (simple heuristic)
            let title = ekEvent.title ?? "未命名日程"
            let kind: ScheduledEvent.Kind
            if title.contains("课") || title.contains("Class") {
                kind = .course
            } else if title.contains("会") || title.contains("Meeting") || title.contains("Sync") {
                kind = .meeting
            } else {
                kind = .uncategorized
            }
            
            return ScheduledEvent(
                id: Self.stableEventID(eventIdentifier: ekEvent.eventIdentifier, startDate: ekEvent.startDate),
                title: title,
                startDate: ekEvent.startDate,
                endDate: ekEvent.endDate,
                kind: kind,
                updatedAt: ekEvent.lastModifiedDate ?? Date(),
                source: .systemCalendar(identifier: ekEvent.eventIdentifier),
                isAllDay: ekEvent.isAllDay
            )
        }.sorted { $0.startDate < $1.startDate }
    }
    
    func specialDayEvents(for date: Date) -> [SpecialDayEvent] {
        guard isAuthorized else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }

        let allowedIDs = selectedCalendarIDs()
        let filteredCalendars = allowedIDs.isEmpty
            ? eventStore.calendars(for: .event)
            : eventStore.calendars(for: .event).filter { allowedIDs.contains($0.calendarIdentifier) }

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: filteredCalendars)
        let events = eventStore.events(matching: predicate)

        var results: [SpecialDayEvent] = []

        for ekEvent in events {
            if ekEvent.calendar?.type == .birthday, let title = ekEvent.title {
                results.append(SpecialDayEvent(title: title, type: .birthday))
                continue
            }

            let calTitle = ekEvent.calendar?.title ?? ""
            let isHolidayCalendar = calTitle.contains("节") || calTitle.contains("假日") || calTitle.contains("Holiday") || calTitle.contains("节日")

            if isHolidayCalendar, let title = ekEvent.title {
                if isSolarTerm(title) {
                    results.append(SpecialDayEvent(title: title, type: .solarTerm))
                } else {
                    results.append(SpecialDayEvent(title: title, type: .holiday))
                }
                continue
            }

            let eventTitle = ekEvent.title ?? ""
            if eventTitle.contains("生日") || eventTitle.localizedCaseInsensitiveContains("birthday") {
                results.append(SpecialDayEvent(title: eventTitle, type: .birthday))
                continue
            }

            if eventTitle.contains("节") && eventTitle.count < 20 && !eventTitle.contains("节目") && !eventTitle.contains("环节") {
                if isSolarTerm(eventTitle) {
                    results.append(SpecialDayEvent(title: eventTitle, type: .solarTerm))
                } else {
                    results.append(SpecialDayEvent(title: eventTitle, type: .holiday))
                }
            }
        }

        return results
    }

    private func isSolarTerm(_ title: String) -> Bool {
        let solarTerms = ["立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
                          "立夏", "小满", "芒种", "夏至", "小暑", "大暑",
                          "立秋", "处暑", "白露", "秋分", "寒露", "霜降",
                          "立冬", "小雪", "大雪", "冬至", "小寒", "大寒"]
        return solarTerms.contains(where: { title.contains($0) })
    }

    func isHolidayCalendar(_ calendar: EKCalendar) -> Bool {
        if calendar.type == .birthday { return true }
        let title = calendar.title
        let holidayKeywords = ["节", "假日", "Holiday", "节日", "假期", "節", "祝日", "放假", "休日", "holiday", "Holidays", "节假日"]
        for kw in holidayKeywords {
            if title.contains(kw) { return true }
        }
        if calendar.type == .subscription {
            for kw in holidayKeywords {
                if title.lowercased().contains(kw.lowercased()) { return true }
            }
        }
        return false
    }

    func isHolidayEvent(_ event: ScheduledEvent) -> Bool {
        guard event.isAllDay,
              case .systemCalendar(let identifier) = event.source else { return false }

        guard let ekEvent = eventStore.event(withIdentifier: identifier),
              let ekCal = ekEvent.calendar else { return false }
        return isHolidayCalendar(ekCal)
    }

    func courseCalendarIDs() -> Set<String> {
        guard let data = UserDefaults.standard.data(forKey: UDK.courseCalendarIdentifiers),
              let ids = try? JSONDecoder().decode(Set<String>.self, from: data) else {
            return []
        }
        return ids
    }

    func saveCourseCalendarIDs(_ ids: Set<String>) {
        if let data = try? JSONEncoder().encode(ids) {
            UserDefaults.standard.set(data, forKey: UDK.courseCalendarIdentifiers)
        }
    }

    func isCourseCalendar(_ calendar: EKCalendar) -> Bool {
        courseCalendarIDs().contains(calendar.calendarIdentifier)
    }

    func toggleCourseCalendar(_ identifier: String) {
        var ids = courseCalendarIDs()
        if ids.contains(identifier) {
            ids.remove(identifier)
        } else {
            ids.insert(identifier)
        }
        saveCourseCalendarIDs(ids)
    }

    func isCourseEvent(_ event: ScheduledEvent) -> Bool {
        guard case .systemCalendar(let identifier) = event.source,
              let ekEvent = eventStore.event(withIdentifier: identifier),
              let ekCal = ekEvent.calendar else { return false }
        return isCourseCalendar(ekCal)
    }

    func holidayOrBirthdayText(for date: Date) -> String? {
        specialDayEvents(for: date).first?.title
    }

    func isSpecialAllDayEvent(_ event: ScheduledEvent) -> Bool {
        guard event.isAllDay else { return false }
        let events = specialDayEvents(for: event.startDate)
        return events.contains(where: { $0.title == event.title })
    }
}
