import Foundation

enum EventSource: Codable, Equatable, Sendable {
    case systemCalendar(identifier: String)
    case notiee
    case ai
    case ics
}

struct ScheduledEvent: Identifiable, Equatable, Sendable, Codable {
    enum Kind: String, CaseIterable, Sendable, Codable {
        case course
        case meeting
        case uncategorized
    }

    enum Status: Equatable, Sendable {
        case completed
        case current
        case upcoming
    }

    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var kind: Kind
    var tagID: UUID?
    var updatedAt: Date
    var source: EventSource
    var notes: String?
    var isAllDay: Bool

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        kind: Kind = .course,
        tagID: UUID? = nil,
        updatedAt: Date = Date(),
        source: EventSource = .notiee,
        notes: String? = nil,
        isAllDay: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.kind = kind
        self.tagID = tagID
        self.updatedAt = updatedAt
        self.source = source
        self.notes = notes
        self.isAllDay = isAllDay
    }

    func contains(_ date: Date) -> Bool {
        startDate <= date && date < endDate
    }

    func status(at date: Date) -> Status {
        if contains(date) {
            return .current
        }

        return date < startDate ? .upcoming : .completed
    }
}
