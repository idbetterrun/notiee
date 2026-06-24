import SwiftUI
import Combine

@MainActor
final class SparkViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var state: SparkState = .idle
    @Published var inputText: String = ""
    @Published var isInputFocused: Bool = false
    @Published var hasSeenPrivacyNotice: Bool = false
    @Published var currentQuestions: [String] = randomQuestions()
    @Published var currentTitle: String = "Spark"
    @Published var isGeneratingTitle: Bool = false
    @Published var injectionWarning: String?
    @Published var memoryActionText: String?
    @Published var isAgentModeEnabled: Bool = false
    @Published var currentToolName: String?
    @Published var agentActions: [AgentAction] = []
    @Published var agentSuggestionMessageID: UUID?
    private var lastUserQuestion: String = ""
    private var currentResponseTask: Task<Void, Never>?

    private let modelPrefs = SparkModelPreferences()
    @Published var sparkModelOverride: String = SparkModelPreferences().modelOverride
    @Published var sparkThinkingLevelID: String? = SparkModelPreferences().thinkingLevelID

    private var textConfigForSpark: AIModelConfiguration {
        settingsStore.loadConfiguration(for: .text)
    }
    var availableModels: [String] {
        let cfg = textConfigForSpark
        return cfg.providerType == .custom ? [cfg.modelName].filter { !$0.isEmpty } : cfg.providerType.predefinedModels
    }
    var effectiveModelName: String {
        modelPrefs.effectiveModelName(globalModel: textConfigForSpark.modelName)
    }
    var thinkingLevels: [ThinkingLevel] {
        ThinkingCapability.forProvider(textConfigForSpark.providerType).levels
    }
    func selectModel(_ name: String) {
        modelPrefs.setModelOverride(name)
        sparkModelOverride = modelPrefs.modelOverride
        if let forced = ModelThinkingPolicy.forcedThinkingLevelID(
            provider: textConfigForSpark.providerType, model: effectiveModelName) {
            modelPrefs.setThinkingLevelID(forced)
            sparkThinkingLevelID = forced
        }
    }

    var lockedThinkingLevelID: String? {
        ModelThinkingPolicy.forcedThinkingLevelID(
            provider: textConfigForSpark.providerType, model: effectiveModelName)
    }
    var isThinkingLocked: Bool { lockedThinkingLevelID != nil }

    func selectThinkingLevel(_ id: String) {
        guard !isThinkingLocked else { return }
        modelPrefs.setThinkingLevelID(id)
        sparkThinkingLevelID = id
    }

    let aiService: any SparkAIServing
    let repository: any SparkConversationCoordinating
    let settingsStore: AppSettingsPersisting
    let recordManager: RecordManager?
    let calendarManager: CalendarManager?
    let folderTagManager: FolderTagManager?

    var recordsProvider: (() -> [NoteRecord])?
    private var loadedFromHistoryID: UUID?
    private var currentConversationId: UUID = UUID()
    private var roundCount: Int { messages.count / 2 }
    private var titleGenerated = false

    init(
        aiService: any SparkAIServing = SparkAIService(),
        repository: any SparkConversationCoordinating = SparkConversationRepository.live,
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live,
        recordManager: RecordManager? = nil,
        calendarManager: CalendarManager? = nil,
        folderTagManager: FolderTagManager? = nil
    ) {
        self.aiService = aiService
        self.repository = repository
        self.settingsStore = settingsStore
        self.recordManager = recordManager
        self.calendarManager = calendarManager
        self.folderTagManager = folderTagManager
        checkPrivacyNotice()
        loadGreeting()
        restoreCurrentConversationIfNeeded()
    }

    // MARK: - Init: restore draft only (no history migration)

    private func restoreCurrentConversationIfNeeded() {
        guard let draft = try? repository.restoreDraft() else { return }
        messages = draft.messages
        currentConversationId = draft.id
        loadedFromHistoryID = draft.id
        if !draft.title.isEmpty {
            currentTitle = draft.title
            titleGenerated = true
        }
        if !messages.isEmpty {
            state = .idle
        }
    }

    // MARK: - Privacy

    private func checkPrivacyNotice() {
        hasSeenPrivacyNotice = settingsStore.loadBool(forKey: "spark_privacy_notice_seen", defaultValue: false)
    }

    func markPrivacyNoticeSeen() {
        settingsStore.saveBool(true, forKey: "spark_privacy_notice_seen")
        hasSeenPrivacyNotice = true
    }

    // MARK: - Greeting persistence

    private func loadGreeting() {
        let emoji = settingsStore.loadString(forKey: "spark_greeting_emoji", defaultValue: "")
        let text = settingsStore.loadString(forKey: "spark_greeting_text", defaultValue: "")
        if emoji.isEmpty || text.isEmpty {
            refreshGreeting()
        }
    }

    func refreshGreeting() {
        let g = GreetingPhrase.random()
        settingsStore.saveString(g.emoji, forKey: "spark_greeting_emoji")
        settingsStore.saveString(g.text, forKey: "spark_greeting_text")
    }

    var greetingEmoji: String { settingsStore.loadString(forKey: "spark_greeting_emoji", defaultValue: "👋") }
    var greetingText: String {
        let saved = settingsStore.loadString(forKey: "spark_greeting_text", defaultValue: "")
        return saved.isEmpty ? String(localized: "嗨") : saved
    }

    // MARK: - Send Message

    func sendMessage() {
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, state != .loading else { return }

        if SparkAIService.containsInjectionPattern(t) {
            injectionWarning = String(localized: "输入包含不安全的指令，请修改后重试")
            return
        }
        injectionWarning = nil

        inputText = ""; state = .loading
        let userMsg = ChatMessage(role: .user, content: t)
        messages.append(userMsg)
        currentResponseTask = Task { await processQuestion(t, userMsg) }
    }

    func cancelResponse() {
        currentResponseTask?.cancel()
        currentResponseTask = nil
        if let last = messages.last, last.role == .assistant, last.content.isEmpty {
            messages.removeLast()
        }
        currentToolName = nil
        state = messages.isEmpty ? .idle : .loaded
        saveCurrentDraft()
    }

    func sendQuestion(_ q: String) { inputText = q; sendMessage() }

    private func processQuestion(_ q: String, _ userMsg: ChatMessage) async {
        if !NetworkMonitor.shared.isConnected {
            messages.append(ChatMessage(role: .assistant, content: String(localized: "网络不可用，无法进行 AI 问答。请检查网络后重试。")))
            state = .offline
            saveCurrentDraft()
            return
        }

        let aid = UUID()
        messages.append(ChatMessage(id: aid, role: .assistant, content: ""))

        do {
            let allRecs = recordsProvider?() ?? []
            let recentRounds = buildRecentRounds()
            let upcoming = calendarManager?.allEvents ?? []

            let (full, tokens) = try await withCheckedThrowingContinuation { cont in
                let service = aiService
                let recs = allRecs
                let rounds = recentRounds
                let question = q
                let events = upcoming
                Task.detached {
                    do {
                        let result = try await service.ask(question: question, with: recs, recentRounds: rounds, upcomingEvents: events)
                        cont.resume(returning: result)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            aiService.accumulatePublic(tokens)

            // Offload post-processing to background
            let service = aiService
            let all = allRecs.filter { !$0.isDeleted }.sorted { $0.capturedAt > $1.capturedAt }
            let (clean, ops, cits) = await Task.detached {
                let (clean, ops) = service.extractMemory(from: full)
                var cIdx = service.extractCitations(from: clean, recordCount: all.count)
                if cIdx.isEmpty {
                    cIdx = service.extractCitationsFallback(from: clean, records: all)
                }
                let cits: [Citation] = cIdx.compactMap { idx in
                    guard idx < all.count else { return nil }
                    let r = all[idx]
                    return Citation(recordID: r.id, title: r.title, capturedAt: r.capturedAt)
                }
                // Strip inline [来源N] markers AFTER extraction so citations are still parsed correctly.
                let cleanStripped = SparkAIService.stripCitationMarkers(clean)
                return (cleanStripped, ops, cits)
            }.value

            if Task.isCancelled { return }

            // Update UI
            if let idx = messages.firstIndex(where: { $0.id == aid }) {
                messages[idx] = ChatMessage(id: aid, role: .assistant, content: clean, citations: cits)
            }
            state = .loaded

            if !isAgentModeEnabled, SparkIntentDetector.looksLikeActionRequest(q) {
                agentSuggestionMessageID = aid
                lastUserQuestion = q
            } else {
                agentSuggestionMessageID = nil
            }

            // Memory operations
            let ms = SparkMemoryStore.live
            var memoryCount = 0
            for (k, v) in ops.toSet { ms.set(k, value: v); memoryCount += 1 }
            for (k, v) in ops.toUpdate { ms.set(k, value: v); memoryCount += 1 }
            for k in ops.toDelete { ms.delete(k); memoryCount += 1 }
            if memoryCount > 0 {
                withAnimation(.easeInOut) { memoryActionText = String(localized: "✓ 已记忆") }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(.easeInOut) {
                        if memoryActionText == String(localized: "✓ 已记忆") { memoryActionText = nil }
                    }
                }
            }

            // Title + save (always upsert, no loadedFromHistoryID guard)
            Task {
                await generateAndSyncTitle()
                saveToHistory()
            }

            triggerMemoryCompressionIfNeeded()

            if SparkAIService.containsPersonalInfoPattern(q) {
                triggerMemoryPipeline(userMessage: q, assistantResponse: clean)
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == aid }) { messages.remove(at: idx) }
            messages.append(ChatMessage(role: .assistant, content: "抱歉，出错了：\(error.localizedDescription)"))
            state = .error(error.localizedDescription)
        }

        saveCurrentDraft()
    }

    // MARK: - Draft persistence

    private func saveCurrentDraft() {
        let draft = SparkConversationDraft(
            id: currentConversationId,
            title: currentTitle,
            messages: messages
        )
        try? repository.saveDraft(draft)
    }

    // MARK: - History persistence (always upsert)

    private func saveToHistory() {
        let msgs = messages
        let id = currentConversationId
        let title = currentTitle
        Task.detached(priority: .utility) { [repository] in
            try? repository.upsertHistory(from: msgs, id: id, title: title)
        }
    }

    // MARK: - Memory Pipeline

    private func triggerMemoryPipeline(userMessage: String, assistantResponse: String) {
        let service = aiService
        Task.detached(priority: .background) {
            await service.extractMemoryFromInput(userMessage: userMessage, assistantResponse: assistantResponse)
        }
    }

    // MARK: - Memory Compression

    private func buildRecentRounds() -> [ConversationRound] {
        var rounds: [ConversationRound] = []
        var i = 0
        let msgs = messages
        let endIndex: Int = {
            if let last = msgs.last, last.role == .assistant, last.content.isEmpty {
                return msgs.count - 1
            }
            return msgs.count
        }()
        while i + 1 < endIndex {
            if msgs[i].role == .user, msgs[i + 1].role == .assistant {
                rounds.append(ConversationRound(userMessage: msgs[i], assistantMessage: msgs[i + 1]))
                i += 2
            } else { i += 1 }
        }
        return rounds
    }

    private func triggerMemoryCompressionIfNeeded() {
        guard roundCount >= SparkAIService.memoryTriggerRoundCount else { return }
        let msgs = messages
        let service = aiService
        Task.detached(priority: .background) {
            let rounds = await Self.buildRounds(from: msgs)
            let lastCompressed = UserDefaults.standard.integer(forKey: UDK.sparkLastMemoryCompressionRounds)
            guard rounds.count > lastCompressed else { return }
            await service.compressMemory(from: rounds)
            UserDefaults.standard.set(rounds.count, forKey: UDK.sparkLastMemoryCompressionRounds)
        }
    }

    private static nonisolated func buildRounds(from msgs: [ChatMessage]) -> [ConversationRound] {
        var rounds: [ConversationRound] = []; var i = 0
        while i + 1 < msgs.count {
            if msgs[i].role == .user, msgs[i + 1].role == .assistant {
                rounds.append(ConversationRound(userMessage: msgs[i], assistantMessage: msgs[i + 1]))
                i += 2
            } else { i += 1 }
        }
        return rounds
    }

    // MARK: - Title

    private static let modelNameKeywords: Set<String> = [
        "deepseek", "qwen", "gpt", "claude", "chatgpt", "openai", "anthropic",
        "minimax", "glm", "ernie", "spark", "doubao", "gemini", "llama",
        "通义", "千问", "文心", "一言", "智谱", "豆包", "星火",
    ]

    private static let titleTriggerRoundCount = 1

    private func generateAndSyncTitle() async {
        guard !titleGenerated else { return }
        guard let first = messages.first(where: { $0.role == .user })?.content,
              !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if currentTitle == "Spark" || currentTitle == String(localized: "新对话") {
            if let neutralTitle = clientSideTitle(from: first) {
                currentTitle = neutralTitle
            } else {
                fallbackTitle(from: first)
            }
        }

        guard roundCount >= Self.titleTriggerRoundCount else { return }
        titleGenerated = true
        isGeneratingTitle = true

        let rounds = buildRecentRounds()
        do {
            let title = try await aiService.generateContextualTitle(from: Array(rounds.suffix(3)))
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !containsModelName(trimmed) {
                currentTitle = trimmed
            }
        } catch { }
        isGeneratingTitle = false
    }

    private func containsModelName(_ title: String) -> Bool {
        let lower = title.lowercased()
        return Self.modelNameKeywords.contains { lower.contains($0) }
    }

    private func clientSideTitle(from message: String) -> String? {
        let t = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        let greetingPatterns = ["你好", "hi", "hello", "嗨", "hey", "在吗", "在么", "早上好", "下午好", "晚上好"]
        let identityPatterns = ["你是谁", "你叫什么", "你是谁呀", "你的名字", "你叫什么名字", "who are you", "what's your name", "what is your name"]
        if greetingPatterns.contains(where: { lower.contains($0.lowercased()) }) {
            return String(localized: "用户问候")
        }
        if identityPatterns.contains(where: { lower.contains($0.lowercased()) }) {
            return String(localized: "用户询问身份")
        }
        return nil
    }

    private func fallbackTitle(from firstMessage: String) {
        let trimmed = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        // 取首句（到第一个句末标点），再限长，避免裸裁产生碎片
        let firstSentence = trimmed.components(separatedBy: CharacterSet(charactersIn: "。！？.!?\n"))
            .first?.trimmingCharacters(in: .whitespaces) ?? trimmed
        let t = String(firstSentence.prefix(20))
        currentTitle = t.isEmpty ? String(localized: "新对话") : t
    }

    // MARK: - History management

    func newConversation() {
        if roundCount >= SparkAIService.memoryTriggerRoundCount {
            let msgs = messages
            let service = aiService
            Task.detached(priority: .background) {
                let rounds = await Self.buildRounds(from: msgs)
                await service.compressMemory(from: rounds)
            }
        }

        guard !messages.isEmpty else { currentQuestions = randomQuestions(); return }

        let msgs = messages
        let title = currentTitle
        let convId = currentConversationId

        Task.detached(priority: .utility) { [repository] in
            try? repository.upsertHistory(from: msgs, id: convId, title: title)
        }

        messages = []
        try? repository.clearDraft()
        state = .idle; inputText = ""
        currentQuestions = randomQuestions()
        refreshGreeting()
        currentTitle = "Spark"
        isGeneratingTitle = false
        titleGenerated = false
        loadedFromHistoryID = nil
        currentConversationId = UUID()
    }

    func loadConversation(_ saved: SavedConversation) {
        messages = saved.messages
        state = .idle
        loadedFromHistoryID = saved.id
        currentTitle = saved.title
        currentConversationId = saved.id
        titleGenerated = true
        isGeneratingTitle = false

        let draft = SparkConversationDraft(id: saved.id, title: saved.title, messages: saved.messages)
        try? repository.saveDraft(draft)
    }

    func deleteConversations(_ ids: Set<UUID>) {
        Task.detached(priority: .utility) { [repository] in
            try? repository.deleteFromHistory(ids)
        }
    }

    // MARK: - Agent Mode

    func acceptAgentSuggestion() {
        let q = lastUserQuestion
        agentSuggestionMessageID = nil
        isAgentModeEnabled = true
        guard !q.isEmpty else { return }
        inputText = q
        runAgent()
    }

    func sendOrRun() {
        if isAgentModeEnabled {
            runAgent()
        } else {
            sendMessage()
        }
    }

    func runAgent() {
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, state != .loading else { return }

        if SparkAIService.containsInjectionPattern(t) {
            injectionWarning = String(localized: "输入包含不安全的指令，请修改后重试")
            return
        }
        injectionWarning = nil

        inputText = ""; state = .loading
        let userMsg = ChatMessage(role: .user, content: t)
        messages.append(userMsg)
        agentActions = []

        currentResponseTask = Task { await executeAgentPipeline(t) }
    }

    private func makeAgentExecutor() -> AgentExecutor? {
        guard let recordManager, let calendarManager, let folderTagManager else { return nil }

        let embeddingModel = UserDefaults.standard.string(forKey: "spark.semanticSearch.embeddingModel") ?? "text-embedding-3-small"
        let cloud = CloudEmbeddingService(configProvider: { [settingsStore] in
            let cfg = settingsStore.loadConfiguration(for: .text)
            return CloudEmbeddingService.Config(endpoint: cfg.activeEndpoint, apiKey: cfg.apiKey, model: embeddingModel)
        })
        let hybrid = HybridEmbeddingService(
            local: LocalEmbeddingService(),
            cloud: cloud,
            preferCloud: { UserDefaults.standard.bool(forKey: "spark.semanticSearch.useCloud") }
        )
        let searchEngine = SemanticSearchEngine(embeddingService: hybrid, index: .live)

        let tools: [any AgentTool] = [
            NoteSearchTool(recordManager: recordManager, searchEngine: searchEngine),
            NoteGetDetailTool(recordManager: recordManager),
            NoteCreateTool(recordManager: recordManager, folderTagManager: folderTagManager),
            NoteUpdateTool(recordManager: recordManager),
            TodoListTool(recordManager: recordManager),
            TodoCreateTool(recordManager: recordManager),
            TodoCompleteTool(recordManager: recordManager),
            CalendarQueryTool(calendarManager: calendarManager),
            DateInfoTool(),
            ScheduleCreateTool(calendarManager: calendarManager),
            ScheduleUpdateTool(calendarManager: calendarManager),
            MemoryManageTool(memoryStore: SparkMemoryStore.live),
            WebFetchTool()
        ]
        let registry = AgentToolRegistry(tools: tools)
        let trustManager = AgentTrustManager(settingsStore: settingsStore)
        let actionStore = AgentActionStore()
        return AgentExecutor(aiService: aiService, toolRegistry: registry, actionStore: actionStore, trustManager: trustManager)
    }

    private func executeAgentPipeline(_ question: String) async {
        guard NetworkMonitor.shared.isConnected else {
            messages.append(ChatMessage(role: .assistant, content: String(localized: "网络不可用，无法进行 AI 问答。")))
            state = .offline; saveCurrentDraft(); return
        }

        guard let executor = makeAgentExecutor() else {
            messages.append(ChatMessage(role: .assistant, content: "Agent 模式需要完整的数据访问权限，请检查设置。"))
            state = .error("Agent initialization failed"); saveCurrentDraft(); return
        }

        do {
            let (text, _, _) = try await executor.run(
                userMessage: question,
                conversationHistory: messages,
                onToolCallStart: { [weak self] toolName in
                    Task { @MainActor in self?.currentToolName = toolName }
                },
                onToolCallEnd: { [weak self] action in
                    Task { @MainActor in self?.agentActions.append(action) }
                }
            )

            if Task.isCancelled { return }

            messages.append(ChatMessage(role: .assistant, content: text))
            state = .loaded
            saveCurrentDraft()
            Task {
                await generateAndSyncTitle()
                saveToHistory()
            }

        } catch {
            messages.append(ChatMessage(role: .assistant, content: "Agent 执行出错：\(error.localizedDescription)"))
            state = .error(error.localizedDescription)
            saveCurrentDraft()
        }
    }
}
