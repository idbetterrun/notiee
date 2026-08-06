import Foundation

enum AgentToolPermission: String, Codable, Sendable {
    case read
    case write
    case destructive
}

@MainActor
protocol AgentTool: AnyObject {
    var name: String { get }
    var description: String { get }
    var permission: AgentToolPermission { get }
    var visibleToModel: Bool { get }
    var parametersSchema: AgentToolParametersSchema { get }
    func execute(parameters: [String: Any]) async throws -> AgentToolResult
}

extension AgentTool {
    var visibleToModel: Bool { true }
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
    private let dataStorage: Data?
    let undoAction: AgentUndoAction?
    let shouldTerminate: Bool

    var data: [String: Any]? {
        guard let dataStorage else { return nil }
        return try? JSONSerialization.jsonObject(with: dataStorage) as? [String: Any]
    }

    init(success: Bool, message: String, data: [String: Any]?,
         undoAction: AgentUndoAction?, shouldTerminate: Bool = false) {
        self.success = success
        self.message = message
        self.dataStorage = data.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        self.undoAction = undoAction
        self.shouldTerminate = shouldTerminate
    }
}

struct AgentUndoAction: Sendable {
    let toolName: String
    let description: String
    private let undoParametersData: Data
    let snapshotPath: String?

    init(toolName: String, description: String, undoParameters: [String: Any], snapshotPath: String?) {
        self.toolName = toolName
        self.description = description
        self.undoParametersData = (try? JSONSerialization.data(withJSONObject: undoParameters)) ?? Data()
        self.snapshotPath = snapshotPath
    }

    var undoParameters: [String: Any] {
        (try? JSONSerialization.jsonObject(with: undoParametersData) as? [String: Any]) ?? [:]
    }
}
