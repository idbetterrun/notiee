import Foundation

final class NoteGetDetailTool: AgentTool {
    let name = "note_get_detail"
    let description = "获取单条拍记的完整内容，包括标题、详细内容、摘要和创建时间"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "record_id": AgentToolProperty(type: "string", description: "拍记ID", enumValues: nil, items: nil)
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
        guard let record = recordManager.records.first(where: { $0.id == recordID }) else {
            return AgentToolResult(success: false, message: "未找到ID为 \(recordIDStr) 的拍记", data: nil, undoAction: nil)
        }

        let message = """
        拍记详情：
        标题：\(record.title)
        创建时间：\(record.capturedAt.formatted(date: .complete, time: .shortened))
        摘要：\(record.summary)
        详细内容：\(record.detailedContent.isEmpty ? "（无）" : record.detailedContent)
        收藏状态：\(record.isFavorite ? "已收藏" : "未收藏")
        """

        return AgentToolResult(success: true, message: message, data: nil, undoAction: nil)
    }
}
