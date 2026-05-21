import Foundation

struct ScheduledEvent: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
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
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        kind: Kind = .course,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.kind = kind
        self.updatedAt = updatedAt
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
