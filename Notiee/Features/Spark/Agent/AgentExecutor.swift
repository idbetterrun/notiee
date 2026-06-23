import Foundation

@MainActor
final class AgentExecutor {
    private let aiService: any SparkAIServing
    private let toolRegistry: AgentToolRegistry
    private let actionStore: AgentActionStore
    private let trustManager: AgentTrustManager

    private let maxIterations = 5
    private var currentActions: [AgentAction] = []

    init(
        aiService: any SparkAIServing,
        toolRegistry: AgentToolRegistry,
        actionStore: AgentActionStore,
        trustManager: AgentTrustManager
    ) {
        self.aiService = aiService
        self.toolRegistry = toolRegistry
        self.actionStore = actionStore
        self.trustManager = trustManager
    }

    func run(
        userMessage: String,
        conversationHistory: [ChatMessage],
        onToolCallStart: @escaping (String) -> Void,
        onToolCallEnd: @escaping (AgentAction) -> Void
    ) async throws -> (text: String, summary: String, actionIDs: [UUID]) {
        currentActions = []

        var messages = buildInitialMessages(userMessage: userMessage, history: conversationHistory)
        let trustLevel = trustManager.currentLevel
        var iteration = 0

        while iteration < maxIterations {
            iteration += 1

            let response = try await aiService.agentChat(
                messages: messages,
                tools: toolRegistry.openAITools(for: trustLevel)
            )

            guard !response.toolCalls.isEmpty else {
                return (response.text, buildActionSummary(), currentActions.map { $0.id })
            }

            messages.append(assistantMessageWithToolCalls(response.toolCalls))

            for toolCall in response.toolCalls {
                onToolCallStart(toolCall.name)

                let action = await executeToolCall(toolCall)
                onToolCallEnd(action)

                var toolContent = action.result.message
                if let dataJSON = action.result.dataJSON {
                    toolContent += "\n\n[结构化数据，可直接用于后续工具的 id 参数]\n" + dataJSON
                }
                messages.append([
                    "role": "tool",
                    "tool_call_id": toolCall.id,
                    "content": toolContent
                ])

                currentActions.append(action)
                actionStore.save(action)

                if action.result.shouldTerminate {
                    return (response.text, buildActionSummary(), currentActions.map { $0.id })
                }
            }
        }

        messages.append(["role": "user", "content": "请基于以上工具执行结果，用与用户相同的语言总结你完成了哪些操作，并回复用户。"])
        let finalResponse = try await aiService.agentChat(messages: messages, tools: [])
        return (finalResponse.text, buildActionSummary(), currentActions.map { $0.id })
    }

    private func executeToolCall(_ call: AgentToolCall) async -> AgentAction {
        guard let tool = toolRegistry.get(call.name) else {
            return AgentAction(
                toolName: call.name,
                parameters: call.parameters,
                result: AgentToolResultData(success: false, message: "未知工具: \(call.name)", shouldTerminate: false, undoAction: nil)
            )
        }

        guard tool.permission.isAllowed(by: trustManager.currentLevel) else {
            return AgentAction(
                toolName: call.name,
                parameters: call.parameters,
                result: AgentToolResultData(success: false, message: "权限不足：操作 \(call.name) 需要更高信任级别", shouldTerminate: true, undoAction: nil)
            )
        }

        do {
            let result = try await tool.execute(parameters: call.parameters)
            let undoData: AgentUndoActionData? = {
                guard let undo = result.undoAction else { return nil }
                let paramsData = (try? JSONSerialization.data(withJSONObject: undo.undoParameters)) ?? Data()
                return AgentUndoActionData(
                    toolName: undo.toolName,
                    description: undo.description,
                    undoParametersData: paramsData,
                    snapshotPath: undo.snapshotPath
                )
            }()
            let shouldTerminate = result.shouldTerminate
            let dataJSON: String? = {
                guard let data = result.data, !data.isEmpty,
                      let json = try? JSONSerialization.data(withJSONObject: data) else { return nil }
                return String(data: json, encoding: .utf8)
            }()
            return AgentAction(
                toolName: call.name,
                parameters: call.parameters,
                result: AgentToolResultData(success: result.success, message: result.message, shouldTerminate: shouldTerminate, undoAction: undoData, dataJSON: dataJSON)
            )
        } catch {
            return AgentAction(
                toolName: call.name,
                parameters: call.parameters,
                result: AgentToolResultData(success: false, message: "工具执行失败: \(error.localizedDescription)", shouldTerminate: false, undoAction: nil)
            )
        }
    }

    private func buildInitialMessages(userMessage: String, history: [ChatMessage]) -> [[String: Any]] {
        var messages: [[String: Any]] = []
        messages.append(["role": "system", "content": buildAgentSystemPrompt()])

        let recentHistory = history.suffix(10)
        for msg in recentHistory {
            let role = msg.role == .user ? "user" : "assistant"
            messages.append(["role": role, "content": msg.content])
        }

        messages.append(["role": "user", "content": userMessage])
        return messages
    }

    private func assistantMessageWithToolCalls(_ calls: [AgentToolCall]) -> [String: Any] {
        let tcArray = calls.map { call -> [String: Any] in
            var funcDef: [String: Any] = ["name": call.name]
            if let data = try? JSONSerialization.data(withJSONObject: call.parameters),
               let args = String(data: data, encoding: .utf8) {
                funcDef["arguments"] = args
            }
            return ["id": call.id, "type": "function", "function": funcDef]
        }
        return ["role": "assistant", "content": NSNull(), "tool_calls": tcArray]
    }

    private func buildActionSummary() -> String {
        guard !currentActions.isEmpty else { return "" }
        return currentActions.map { action in
            let icon = action.result.success ? "✓" : "✗"
            return "\(icon) \(action.toolName): \(action.result.message)"
        }.joined(separator: "\n")
    }

    private func buildAgentSystemPrompt() -> String {
        SparkPromptFragments.agentSystemPrompt(now: Date())
    }

    func undoAction(_ undoAction: AgentUndoActionData) async throws {
        if let path = undoAction.snapshotPath {
            let snapshotData = try actionStore.readSnapshot(path: path)
            _ = try JSONDecoder().decode([NoteRecord].self, from: snapshotData)
            try actionStore.deleteSnapshot(path: path)
        } else {
            guard let tool = toolRegistry.get(undoAction.toolName) else {
                throw AgentActionStoreError.toolNotFound
            }
            _ = try await tool.execute(parameters: undoAction.undoParametersDict)
        }
    }
}
