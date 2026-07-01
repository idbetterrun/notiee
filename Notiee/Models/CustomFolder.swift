import Foundation

struct CustomFolder: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    
    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}
