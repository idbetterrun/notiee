import Foundation
import EventKit

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    
    private let eventStore = EKEventStore()
    
    @Published private(set) var isAuthorized = false
    
    private init() {
        checkAuthorizationStatus()
    }
    
    private func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            isAuthorized = (status == .fullAccess || status == .writeOnly)
        } else {
            isAuthorized = (status == .authorized)
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
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
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
                id: UUID(),
                title: title,
                startDate: ekEvent.startDate,
                endDate: ekEvent.endDate,
                kind: kind,
                updatedAt: ekEvent.lastModifiedDate ?? Date(),
                source: .systemCalendar(identifier: ekEvent.eventIdentifier)
            )
        }.sorted { $0.startDate < $1.startDate }
    }
}
