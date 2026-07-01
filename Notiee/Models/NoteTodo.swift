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

    enum CodingKeys: String, CodingKey {
        case id, recordID, content, isCompleted, createdAt, dueDate, hasReminder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        recordID = try c.decodeIfPresent(UUID.self, forKey: .recordID)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        hasReminder = try c.decodeIfPresent(Bool.self, forKey: .hasReminder) ?? false
    }
}
