import Foundation
import OSLog

/// Notti for the Notiee (free) version: routes the network calls through the
/// backend `POST /ai/chat` (keys live server-side) while reusing
/// `NottiAIService` for pure-local prompt assembly and citation extraction.
/// Notiee-target only.
///
/// Free tier is locked to `deepseek-v4-flash` and has no Agent mode (Phase 2.5
/// tightens the tier gating; the backend re-checks the tier regardless).
final class BackendNottiAIService: NottiAIServing, @unchecked Sendable {
    /// Composed BYOK service, used only for its local (non-network) helpers.
    private let local: NottiAIService
    private let api: BackendAPIClient

    /// 用户选中的文本模型（与笔记处理共用同一份 `CuratedModelSelection`）。
    private let selection = CuratedModelSelection.live

    init(api: BackendAPIClient = .shared) {
        self.local = NottiAIService()
        self.api = api
    }

    // MARK: - Chat

    func ask(question: String, recall: RecalledRecords, recentRounds: [ConversationRound], upcomingEvents: [ScheduledEvent], pinnedRecordIDs: [UUID]) async throws -> (text: String, tokens: Int) {
        let systemPrompt = local.buildSystemPrompt(
            recall: recall, recentRounds: recentRounds, upcomingEvents: upcomingEvents, pinnedRecordIDs: pinnedRecordIDs)
        let userPrompt = "用户说：\(question)"

        let result = try await chat(
            messages: [["role": "user", "content": userPrompt]],
            system: systemPrompt)
        accumulatePublic(result.tokens)
        return result
    }

    // MARK: - Title generation
    // Prompts mirror NottiAIService's; only the transport differs (backend vs BYOK).

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
        let context = rounds.map { "用户: \($0.userMessage.content)\nNotti: \($0.assistantMessage.content)" }
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

    // MARK: - Agent (backend tool-calling passthrough)

    /// Runs one Agent turn through the backend `POST /ai/agent` endpoint, which
    /// forwards `messages` + OpenAI-format `tools` to the model and returns the
    /// assistant text plus any `tool_calls`. The tool *execution* still happens
    /// on-device in `AgentExecutor`; the backend only relays the model call so the
    /// key stays server-side. Mirrors `NottiAIService.agentChat` (BYOK) in shape,
    /// so the executor consumes both identically.
    ///
    /// If the backend hasn't shipped `/ai/agent` yet it replies `NOT_IMPLEMENTED`,
    /// which we surface as a friendly "coming soon" message rather than a raw error.
    func agentChat(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AgentChatResponse {
        let model = selection.textModelID(for: CurrentEntitlement.tier)
        var body: [String: Any] = ["messages": messages, "model": model]
        if !tools.isEmpty { body["tools"] = tools }

        let json: [String: Any]
        do {
            json = try await api.postJSON(
                path: "ai/agent", body: body,
                authorized: true, timeout: BackendAPIClient.Timeout.aiProcess)
        } catch let error as BackendError where error.code == .notImplemented || error.httpStatus == 404 {
            // `/ai/agent` not deployed yet: the backend may reply either a
            // structured NOT_IMPLEMENTED or a bare 404 (Express default HTML,
            // "Cannot POST /ai/agent"). Treat both as "coming soon", not a crash.
            throw NottiAIError.apiError(String(localized: "Agent 模式暂不支持，敬请期待"))
        }

        let text = json["text"] as? String ?? ""
        let tokens = json["tokensUsed"] as? Int ?? 0
        accumulatePublic(tokens)

        let rawToolCalls = json["toolCalls"] as? [[String: Any]] ?? []
        let toolCalls = Self.parseToolCalls(rawToolCalls)

        return AgentChatResponse(text: text, toolCalls: toolCalls, tokensUsed: tokens)
    }

    /// Accepts both Anthropic-style (`{id, name, input}`) and OpenAI-style
    /// (`{id, function:{name, arguments}}`) tool-call shapes, matching the BYOK
    /// parser so the backend can relay either upstream format unchanged.
    private static func parseToolCalls(_ raw: [[String: Any]]) -> [AgentToolCall] {
        raw.compactMap { tc in
            if tc["input"] != nil {
                guard let id = tc["id"] as? String,
                      let name = tc["name"] as? String,
                      let input = tc["input"] as? [String: Any] else { return nil }
                return AgentToolCall(id: id, name: name, parameters: input)
            } else {
                guard let id = tc["id"] as? String,
                      let funcInfo = tc["function"] as? [String: Any],
                      let name = funcInfo["name"] as? String,
                      let argsStr = funcInfo["arguments"] as? String,
                      let argsData = argsStr.data(using: .utf8),
                      let params = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else { return nil }
                return AgentToolCall(id: id, name: name, parameters: params)
            }
        }
    }

    // MARK: - Local delegation (no network)

    func accumulatePublic(_ tokens: Int) { local.accumulatePublic(tokens) }

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

/// Free-target extraction transport. The backend owns the fixed extraction
/// prompt and returns the same strict ADD-only proposal envelope as BYOK.
final class BackendNottiMemoryExtractor: NottiMemoryExtracting, @unchecked Sendable {
    private let api: BackendAPIClient
    private let selection: CuratedModelSelection

    init(
        api: BackendAPIClient = .shared,
        selection: CuratedModelSelection = .live
    ) {
        self.api = api
        self.selection = selection
    }

    func extract(
        job: NottiMemoryExtractionJob,
        candidates: [NottiMemoryExtractionCandidate]
    ) async throws -> [NottiMemoryProposal] {
        let body = Self.makeRequestBody(
            job: job,
            candidates: candidates,
            model: selection.textModelID(for: CurrentEntitlement.tier)
        )
        let json = try await api.postJSON(
            path: "ai/memory/extract",
            body: body,
            authorized: true,
            timeout: BackendAPIClient.Timeout.standard
        )
        return try Self.decodeResponse(json)
    }

    static func makeRequestBody(
        job: NottiMemoryExtractionJob,
        candidates: [NottiMemoryExtractionCandidate],
        model: String
    ) -> [String: Any] {
        let candidateObjects: [[String: Any]] = candidates.prefix(8).map {
            [
                "id": $0.id.uuidString,
                "text": String($0.text.prefix(500)),
                "category": $0.category.rawValue,
                "topicKey": String($0.topicKey.prefix(120)),
            ]
        }
        return [
            "model": model,
            "userMessage": String(job.userMessage.prefix(4_000)),
            "confirmedToolResults": job.confirmedToolResults.prefix(8).map { String($0.prefix(2_000)) },
            "candidates": candidateObjects,
        ]
    }

    static func decodeResponse(_ json: [String: Any]) throws -> [NottiMemoryProposal] {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        return try NottiMemoryProposalDecoder.decode(data)
    }
}
