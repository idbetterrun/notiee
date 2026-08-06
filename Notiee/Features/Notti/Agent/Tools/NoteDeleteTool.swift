import Foundation

@MainActor
final class NoteDeleteTool: AgentTool {
    let name = "note_delete"
    let description = "删除指定拍记（撤销专用，模型不可直接调用）"
    let permission: AgentToolPermission = .destructive
    var visibleToModel: Bool { false }

    let parametersSchema = AgentToolParametersSchema(
        properties: ["record_id": AgentToolProperty(type: "string", description: "要删除的拍记UUID", enumValues: nil, items: nil)],
        required: ["record_id"]
    )

    let recordManager: RecordManager
    init(recordManager: RecordManager) { self.recordManager = recordManager }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let idStr = parameters["record_id"] as? String, let id = UUID(uuidString: idStr) else {
            throw AgentToolError.missingParameter("record_id")
        }
        recordManager.permanentlyDelete(id: id)
        return AgentToolResult(success: true, message: "已删除拍记", data: nil, undoAction: nil)
    }
}
