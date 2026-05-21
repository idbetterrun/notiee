import Foundation

struct NoteTodo: Identifiable, Equatable, Sendable {
    let id: UUID
    var recordID: UUID?
    var content: String
    var isCompleted: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        recordID: UUID?,
        content: String,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordID = recordID
        self.content = content
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
}
