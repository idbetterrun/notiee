import Foundation
import OSLog

/// Spark for the Notiee (free) version: routes the network calls through the
/// backend `POST /ai/chat` (keys live server-side) while reusing
/// `SparkAIService` for all the pure-local work — system-prompt assembly, memory
/// tag parsing, citation extraction. Notiee-target only.
///
/// Free tier is locked to `deepseek-v4-flash` and has no Agent mode (Phase 2.5
/// tightens the tier gating; the backend re-checks the tier regardless).
final class BackendSparkAIService: SparkAIServing, @unchecked Sendable {
    /// Composed BYOK service, used only for its local (non-network) helpers.
    private let local: SparkAIService
    private let memoryStore: SparkMemoryPersisting
    private let api: BackendAPIClient

    /// 用户选中的文本模型（与笔记处理共用同一份 `CuratedModelSelection`）。
    private let selection = CuratedModelSelection.live

    init(memoryStore: SparkMemoryPersisting = SparkMemoryStore.live,
         api: BackendAPIClient = .shared) {
        self.local = SparkAIService(memoryStore: memoryStore)
        self.memoryStore = memoryStore
        self.api = api
    }

    // MARK: - Chat

    func ask(question: String, with allRecords: [NoteRecord], recentRounds: [ConversationRound], upcomingEvents: [ScheduledEvent]) async throws -> (text: String, tokens: Int) {
        let activeRecords = allRecords
            .filter { !$0.isDeleted }
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(SparkAIService.maxRecordsInPrompt)
        let systemPrompt = local.buildSystemPrompt(
            records: Array(activeRecords), recentRounds: recentRounds, upcomingEvents: upcomingEvents)
        let userPrompt = "用户说：\(question)"

        let result = try await chat(
            messages: [["role": "user", "content": userPrompt]],
            system: systemPrompt)
        accumulatePublic(result.tokens)
        return result
    }

    // MARK: - Title generation
    // Prompts mirror SparkAIService's; only the transport differs (backend vs BYOK).

    func generateTitle(for message: String) async throws -> String {
        let userPrompt = """
        你是一个标题生成助手。用不超过15个字总结下面这句话的核心内容，只返回总结文本，不要加引号或其他修饰。

        用户说：\(String(message.prefix(200)))
        """
        let result = try await chat(messages: [["role": "user", "content": userPrompt]], system: nil)
        accumulatePublic(result.tokens)
        return String(result.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
    }

    func generateContextualTitle(from rounds: [ConversationRound]) async throws -> String {
        let context = rounds.map { "用户: \($0.userMessage.content)\nSpark: \($0.assistantMessage.content)" }
            .joined(separator: "\n---\n")
        let userPrompt = """
        为以下对话生成一个高度概括的简短标题。
        语言要求：标题必须与用户使用的语言一致（用户说英文就用英文标题，说中文就用中文标题）。
        长度：不超过 20 个字符。只返回标题文本，不要加引号、标点或其他修饰。

        对话内容：
        \(String(context.prefix(600)))
        """
        let result = try await chat(
            messages: [["role": "user", "content": userPrompt]],
            system: "你是一个标题生成助手。")
        accumulatePublic(result.tokens)
        return String(result.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20))
    }

    // MARK: - Memory pipeline (background, best-effort)

    func extractMemoryFromInput(userMessage: String, assistantResponse: String) async {
        let systemPrompt = """
        你是记忆提取助手。从用户消息中提取个人信息，以 [记忆]键:值[/记忆] 格式输出。
        只提取以下类型的信息：名字、职业、年龄、位置、偏好、习惯、宠物、家庭成员。
        键名使用简洁中文（如「名字」「职业」「位置」「偏好饮品」）。
        如果没有可提取的个人信息，输出「无」。
        不要输出任何其他内容。
        """
        let userPrompt = "用户说：\(userMessage)\n\nSpark回复（供上下文理解）：\(String(assistantResponse.prefix(200)))"
        await runMemoryExtraction(system: systemPrompt, user: userPrompt)
    }

    func compressMemory(from rounds: [ConversationRound]) async {
        var transcript = ""
        for (i, round) in rounds.suffix(10).enumerated() {
            transcript += "用户: \(round.userMessage.content)\nSpark: \(round.assistantMessage.content.prefix(200))\n"
            if i < rounds.count - 1 { transcript += "---\n" }
        }
        let systemPrompt = """
        你是一个记忆整理助手。请从以下对话中提取关于用户的核心标签、偏好、习惯和个人信息。
        以 [记忆]标签:内容[/记忆] 的格式输出，每个标签一行。
        如果发现与已知信息冲突的新信息，以 [更新记忆]标签:新内容[/更新记忆] 的格式输出。
        只提取真正有价值、能帮助未来对话的标签。如果没有什么特别的，输出「无」。
        不要输出任何其他内容。
        """
        await runMemoryExtraction(system: systemPrompt, user: "对话记录：\n\(transcript)")
    }

    private func runMemoryExtraction(system: String, user: String) async {
        do {
            let result = try await chat(messages: [["role": "user", "content": user]], system: system)
            accumulatePublic(result.tokens)
            let (_, ops) = local.extractMemory(from: result.text)
            for (k, v) in ops.toSet { memoryStore.set(k, value: v) }
            for (k, v) in ops.toUpdate { memoryStore.set(k, value: v) }
            for k in ops.toDelete { memoryStore.delete(k) }
        } catch {
            return
        }
    }

    // MARK: - Agent (unsupported on free / no backend tools passthrough yet)

    func agentChat(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AgentChatResponse {
        throw SparkAIError.apiError(String(localized: "Agent 模式暂不支持，敬请期待"))
    }

    // MARK: - Local delegation (no network)

    func accumulatePublic(_ tokens: Int) { local.accumulatePublic(tokens) }

    func extractMemory(from text: String) -> (cleanText: String, ops: SparkAIService.MemoryOperations) {
        local.extractMemory(from: text)
    }

    func extractCitations(from text: String, recordCount: Int) -> [Int] {
        local.extractCitations(from: text, recordCount: recordCount)
    }

    func extractCitationsFallback(from text: String, records: [NoteRecord]) -> [Int] {
        local.extractCitationsFallback(from: text, records: records)
    }

    // MARK: - Transport

    private func chat(messages: [[String: Any]], system: String?) async throws -> (text: String, tokens: Int) {
        let model = selection.textModelID(for: CurrentEntitlement.tier)
        var body: [String: Any] = ["messages": messages, "model": model]
        if let system, !system.isEmpty { body["system"] = system }
        let json = try await api.postJSON(
            path: "ai/chat", body: body,
            authorized: true, timeout: BackendAPIClient.Timeout.standard)
        let text = json["text"] as? String ?? ""
        let tokens = json["tokensUsed"] as? Int ?? 0
        return (text, tokens)
    }
}
