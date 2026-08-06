import Foundation

@MainActor
final class MemorySearchTool: AgentTool {
    let name = "memory_search"
    let description = "按当前问题检索 Notti 的相关用户记忆。结果有数量和字符上限。"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "query": AgentToolProperty(type: "string", description: "要检索的记忆主题或问题")
        ],
        required: ["query"]
    )

    private let coordinator: NottiMemoryCoordinator

    init(coordinator: NottiMemoryCoordinator = .live) {
        self.coordinator = coordinator
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let query = parameters["query"] as? String,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.missingParameter("query")
        }
        let recall = await coordinator.recall(for: String(query.prefix(500)))

        let memories = recall.results.map { result -> [String: Any] in
            [
                "id": result.memory.id.uuidString,
                "text": result.memory.text,
                "category": result.memory.category.rawValue,
            ]
        }
        let message = memories.isEmpty
            ? "没有找到与该问题相关的用户记忆。"
            : "找到 \(memories.count) 条相关用户记忆。"
        return AgentToolResult(
            success: true,
            message: message,
            data: ["memories": memories],
            undoAction: nil
        )
    }
}

@MainActor
final class MemoryForgetTool: AgentTool {
    let name = "memory_forget"
    let description = "永久删除一条指定的 Notti 记忆。仅在用户明确要求遗忘时使用。"
    let permission: AgentToolPermission = .destructive

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "memory_id": AgentToolProperty(type: "string", description: "用户明确要求删除的记忆 UUID")
        ],
        required: ["memory_id"]
    )

    private let repository: NottiMemoryRepository

    init(repository: NottiMemoryRepository = .live) {
        self.repository = repository
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let rawID = parameters["memory_id"] as? String,
              let id = UUID(uuidString: rawID) else {
            throw AgentToolError.missingParameter("memory_id")
        }
        try await repository.hardDelete(id: id)
        return AgentToolResult(
            success: true,
            message: "已永久删除指定记忆。",
            data: ["memory_id": id.uuidString],
            undoAction: nil
        )
    }
}
