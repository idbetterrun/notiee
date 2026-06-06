import Foundation

enum AgentToolPermission: String, Codable, Sendable {
    case read
    case write
    case destructive
}

protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var permission: AgentToolPermission { get }
    var parametersSchema: AgentToolParametersSchema { get }
    func execute(parameters: [String: Any]) async throws -> AgentToolResult
}

struct AgentToolParametersSchema: Sendable {
    let type: String = "object"
    let properties: [String: AgentToolProperty]
    let required: [String]
}

final class AgentToolProperty: @unchecked Sendable {
    let type: String
    let description: String
    let enumValues: [String]?
    let items: AgentToolProperty?

    init(type: String, description: String, enumValues: [String]? = nil, items: AgentToolProperty? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.items = items
    }
}

struct AgentToolResult: Sendable {
    let success: Bool
    let message: String
    let data: [String: Any]?
    let undoAction: AgentUndoAction?
}

struct AgentUndoAction: Sendable {
    let toolName: String
    let description: String
    let undoParameters: [String: Any]
    let snapshotPath: String?
}
