import Foundation

@MainActor
final class NoteCreateTool: AgentTool {
    let name = "note_create"
    let description = "创建一条新的拍记。用于记录新的笔记、想法或信息。"
    let permission: AgentToolPermission = .write

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "title": AgentToolProperty(type: "string", description: "拍记标题", enumValues: nil, items: nil),
            "content": AgentToolProperty(type: "string", description: "拍记详细内容（可选）", enumValues: nil, items: nil),
            "summary": AgentToolProperty(type: "string", description: "一句话摘要（可选但推荐）。提炼内容要点，不要照抄正文。", enumValues: nil, items: nil),
            "event_id": AgentToolProperty(type: "string", description: "关联的日程UUID（可选）", enumValues: nil, items: nil)
        ],
        required: ["title"]
    )

    let recordManager: RecordManager
    let folderTagManager: FolderTagManager

    init(recordManager: RecordManager, folderTagManager: FolderTagManager) {
        self.recordManager = recordManager
        self.folderTagManager = folderTagManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let title = parameters["title"] as? String else {
            throw AgentToolError.missingParameter("title")
        }
        let content = parameters["content"] as? String ?? ""
        // 真摘要：Notti 提供则用，否则留空（不照抄正文截断，避免摘要与正文重复）。
        let summary = (parameters["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let eventID = (parameters["event_id"] as? String).flatMap(UUID.init(uuidString:))
        let folderID = folderTagManager.findOrCreateFolder(named: FolderTagManager.nottiFolderName)

        let newRecord = NoteRecord(
            eventID: eventID,
            folderID: folderID,
            localImagePaths: [],
            title: title,
            summary: summary,
            detailedContent: content,
            processingState: .completed,
            source: .notti
        )
        recordManager.addRecord(newRecord)

        return AgentToolResult(
            success: true,
            message: "已创建拍记「\(title)」",
            data: ["record_id": newRecord.id.uuidString],
            undoAction: AgentUndoAction(
                toolName: "note_delete",
                description: "删除刚刚创建的拍记「\(title)」",
                undoParameters: ["record_id": newRecord.id.uuidString],
                snapshotPath: nil
            )
        )
    }
}
