import Foundation

@MainActor
final class AgentExecutor {
    private let aiService: any NottiAIServing
    private let toolRegistry: AgentToolRegistry
    private let actionStore: AgentActionStore
    private let trustManager: AgentTrustManager
    private let confirmDestructiveAction: (String, [String: Any]) async -> Bool

    private let maxIterations = 5
    private var currentActions: [AgentAction] = []

    init(
        aiService: any NottiAIServing,
        toolRegistry: AgentToolRegistry,
        actionStore: AgentActionStore,
        trustManager: AgentTrustManager,
        confirmDestructiveAction: @escaping (String, [String: Any]) async -> Bool = { _, _ in false }
    ) {
        self.aiService = aiService
        self.toolRegistry = toolRegistry
        self.actionStore = actionStore
        self.trustManager = trustManager
        self.confirmDestructiveAction = confirmDestructiveAction
    }

    func run(
        userMessage: String,
        conversationHistory: [ChatMessage],
        onToolCallStart: @escaping (String) -> Void,
        onToolCallEnd: @escaping (AgentAction) -> Void
    ) async throws -> (text: String, summary: String, actionIDs: [UUID], memoryIDs: [UUID]) {
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
                return successfulResult(text: response.text)
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
                    return successfulResult(text: response.text)
                }
            }
        }

        messages.append(["role": "user", "content": "请基于以上工具执行结果，用与用户相同的语言总结你完成了哪些操作，并回复用户。"])
        let finalResponse = try await aiService.agentChat(messages: messages, tools: [])
        return successfulResult(text: finalResponse.text)
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

        if tool.permission == .destructive {
            let isConfirmed = await confirmDestructiveAction(tool.name, call.parameters)
            if !isConfirmed {
                return AgentAction(
                    toolName: call.name,
                    parameters: call.parameters,
                    result: AgentToolResultData(
                        success: false,
                        message: "用户未确认破坏性操作，未执行 \(call.name)",
                        shouldTerminate: true,
                        undoAction: nil
                    )
                )
            }
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

    private func buildConfirmedToolSummary() -> String {
        Self.confirmedToolSummary(from: currentActions)
    }

    private func successfulResult(
        text: String
    ) -> (text: String, summary: String, actionIDs: [UUID], memoryIDs: [UUID]) {
        (
            text,
            buildConfirmedToolSummary(),
            currentActions.map(\.id),
            Self.successfulMemorySearchIDs(from: currentActions)
        )
    }

    nonisolated static func confirmedToolSummary(
        from actions: [AgentAction],
        characterLimit: Int = 4_000
    ) -> String {
        guard characterLimit > 0 else { return "" }
        let successful = actions
            .filter(\.result.success)
            .map { "\($0.toolName): \($0.result.message)" }
            .joined(separator: "\n")
        return String(successful.prefix(characterLimit))
    }

    nonisolated static func successfulMemorySearchIDs(from actions: [AgentAction]) -> [UUID] {
        var seen = Set<UUID>()
        var output: [UUID] = []
        for action in actions where action.toolName == "memory_search" && action.result.success {
            guard let dataJSON = action.result.dataJSON,
                  let data = dataJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let memories = object["memories"] as? [[String: Any]] else { continue }
            for memory in memories {
                guard let rawID = memory["id"] as? String,
                      let id = UUID(uuidString: rawID),
                      seen.insert(id).inserted else { continue }
                output.append(id)
            }
        }
        return output
    }

    private func buildAgentSystemPrompt() -> String {
        NottiPromptFragments.agentSystemPrompt(now: Date())
    }

    func undoAction(_ undoAction: AgentUndoActionData) async throws {
        guard undoAction.snapshotPath == nil else {
            throw AgentActionStoreError.notUndoable
        }
        guard let tool = toolRegistry.get(undoAction.toolName) else {
            throw AgentActionStoreError.toolNotFound
        }
        _ = try await tool.execute(parameters: undoAction.undoParametersDict)
    }
}
