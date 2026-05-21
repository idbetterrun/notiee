import Foundation

struct ScheduleMatcher {
    func currentEvent(from events: [ScheduledEvent], at date: Date) -> ScheduledEvent? {
        events
            .filter { $0.contains(date) }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }

                return lhs.startDate > rhs.startDate
            }
            .first
    }
}
