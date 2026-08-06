import Foundation

enum CustomFolderSystemRole: String, Codable, Sendable {
    case nottiGenerated
}

struct CustomFolder: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date
    var systemRole: CustomFolderSystemRole?
    
    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        systemRole: CustomFolderSystemRole? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.systemRole = systemRole
    }
}
