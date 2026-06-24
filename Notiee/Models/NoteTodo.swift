import Foundation

struct NoteTodo: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    var recordID: UUID?
    var content: String
    var isCompleted: Bool
    var createdAt: Date
    var dueDate: Date?
    var hasReminder: Bool

    init(
        id: UUID = UUID(),
        recordID: UUID?,
        content: String,
        isCompleted: Bool = false,
        createdAt: Date = Date(),
        dueDate: Date? = nil,
        hasReminder: Bool = false
    ) {
        self.id = id
        self.recordID = recordID
        self.content = content
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.hasReminder = hasReminder
    }
}
