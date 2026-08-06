import Foundation

struct AgentToolResultData: Equatable, Codable, Sendable {
    let success: Bool
    let message: String
    let shouldTerminate: Bool
    let undoAction: AgentUndoActionData?
    /// Structured payload (record_id / todo_id / event_id …) serialized as JSON,
    /// fed back to the model so follow-up write tools can reference these IDs.
    var dataJSON: String?

    init(success: Bool, message: String, shouldTerminate: Bool,
         undoAction: AgentUndoActionData?, dataJSON: String? = nil) {
        self.success = success
        self.message = message
        self.shouldTerminate = shouldTerminate
        self.undoAction = undoAction
        self.dataJSON = dataJSON
    }
}

struct AgentUndoActionData: Equatable, Codable, Sendable {
    let toolName: String
    let description: String
    let undoParametersData: Data
    let snapshotPath: String?

    var undoParametersDict: [String: Any] {
        (try? JSONSerialization.jsonObject(with: undoParametersData) as? [String: Any]) ?? [:]
    }
}

struct AgentAction: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let toolName: String
    let parametersData: Data
    let result: AgentToolResultData
    let executedAt: Date

    var parametersDict: [String: Any] {
        (try? JSONSerialization.jsonObject(with: parametersData) as? [String: Any]) ?? [:]
    }

    init(id: UUID = UUID(), toolName: String, parameters: [String: Any], result: AgentToolResultData, executedAt: Date = Date()) {
        self.id = id
        self.toolName = toolName
        self.parametersData = (try? JSONSerialization.data(withJSONObject: parameters)) ?? Data()
        self.result = result
        self.executedAt = executedAt
    }
}

struct AgentActionSummary: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let actions: [AgentAction]
    let timestamp: Date

    var successCount: Int { actions.filter { $0.result.success }.count }
    var totalCount: Int { actions.count }
}
