import Foundation

final class MemoryManageTool: AgentTool {
    let name = "memory_get"
    let description = "获取 Spark 关于用户的记忆信息，如偏好、习惯等"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "key": AgentToolProperty(type: "string", description: "记忆键名（可选，不传则列出全部）", enumValues: nil, items: nil)
        ],
        required: []
    )

    let memoryStore: SparkMemoryStore

    init(memoryStore: SparkMemoryStore) {
        self.memoryStore = memoryStore
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        let allEntries = await memoryStore.allEntries()
        let key = parameters["key"] as? String

        let filtered = key.map { k in allEntries.filter { $0.key == k } } ?? allEntries

        let message = filtered.isEmpty
            ? "暂无关于用户的记忆信息。"
            : "Spark 关于用户的记忆：\n" + filtered.map {
                "  键名: \($0.key) → 内容: \($0.value)"
            }.joined(separator: "\n")

        let memoriesData = filtered.map { ["key": $0.key, "value": $0.value] as [String: Any] }
        return AgentToolResult(success: true, message: message, data: ["memories": memoriesData], undoAction: nil)
    }
}
