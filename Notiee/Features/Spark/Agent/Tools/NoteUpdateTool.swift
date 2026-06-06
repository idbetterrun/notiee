import Foundation

@MainActor
final class NoteUpdateTool: AgentTool {
    let name = "note_update"
    let description = "修改已有拍记的内容，如标题、详细内容或摘要"
    let permission: AgentToolPermission = .write

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "record_id": AgentToolProperty(type: "string", description: "要修改的拍记ID", enumValues: nil, items: nil),
            "title": AgentToolProperty(type: "string", description: "新的标题（可选）", enumValues: nil, items: nil),
            "detailed_content": AgentToolProperty(type: "string", description: "新的详细内容（可选）", enumValues: nil, items: nil),
            "summary": AgentToolProperty(type: "string", description: "新的摘要（可选）", enumValues: nil, items: nil)
        ],
        required: ["record_id"]
    )

    let recordManager: RecordManager

    init(recordManager: RecordManager) {
        self.recordManager = recordManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let recordIDStr = parameters["record_id"] as? String,
              let recordID = UUID(uuidString: recordIDStr) else {
            throw AgentToolError.missingParameter("record_id")
        }
        guard let index = recordManager.records.firstIndex(where: { $0.id == recordID }) else {
            return AgentToolResult(success: false, message: "未找到ID为 \(recordIDStr) 的拍记", data: nil, undoAction: nil)
        }

        let originalRecord = recordManager.records[index]
        var updated = originalRecord
        if let title = parameters["title"] as? String { updated.title = title }
        if let content = parameters["detailed_content"] as? String { updated.detailedContent = content }
        if let summary = parameters["summary"] as? String { updated.summary = summary }
        recordManager.updateRecord(updated)

        return AgentToolResult(
            success: true,
            message: "已更新拍记「\(updated.title)」",
            data: nil,
            undoAction: AgentUndoAction(
                toolName: "note_update",
                description: "恢复拍记「\(originalRecord.title)」的原始内容",
                undoParameters: [
                    "record_id": originalRecord.id.uuidString,
                    "title": originalRecord.title,
                    "detailed_content": originalRecord.detailedContent,
                    "summary": originalRecord.summary
                ],
                snapshotPath: nil
            )
        )
    }
}
