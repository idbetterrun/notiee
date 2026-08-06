import SwiftUI
import Combine

struct NottiDestructiveConfirmation: Identifiable, Equatable {
    let id = UUID()
    let toolName: String
    let detail: String
}

@MainActor
final class NottiViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var state: NottiState = .idle
    @Published var inputText: String = ""
    @Published var isInputFocused: Bool = false
    @Published var hasSeenPrivacyNotice: Bool = false
    @Published var currentQuestions: [String] = randomQuestions()
    @Published var currentTitle: String = "Notti"
    @Published var isGeneratingTitle: Bool = false
    @Published var injectionWarning: String?
    /// 免费档单会话轮数触顶（Notiee+ 恒 false）。View 据此显示「开启新会话 / 升级 Pro」横幅。
    @Published var sessionLimitReached: Bool = false
    @Published var isAgentModeEnabled: Bool = false
    @Published var currentToolName: String?
    @Published var agentActions: [AgentAction] = []
    @Published var agentSuggestionMessageID: UUID?
    @Published var pendingDestructiveConfirmation: NottiDestructiveConfirmation?
    private var lastUserQuestion: String = ""
    private var currentResponseTask: Task<Void, Never>?
    private var destructiveConfirmationContinuation: CheckedContinuation<Bool, Never>?

    private let modelPrefs = NottiModelPreferences()
    @Published var nottiModelOverride: String = NottiModelPreferences().modelOverride
    @Published var nottiThinkingLevelID: String? = NottiModelPreferences().thinkingLevelID

    private var textConfigForNotti: AIModelConfiguration {
        settingsStore.loadConfiguration(for: .text)
    }
    var availableModels: [String] {
        let cfg = textConfigForNotti
        return cfg.providerType == .custom ? [cfg.modelName].filter { !$0.isEmpty } : cfg.providerType.predefinedModels
    }
    var effectiveModelName: String {
        modelPrefs.effectiveModelName(globalModel: textConfigForNotti.modelName)
    }
    var thinkingLevels: [ThinkingLevel] {
        ThinkingCapability.forProvider(textConfigForNotti.providerType).levels
    }
    func selectModel(_ name: String) {
        modelPrefs.setModelOverride(name)
        nottiModelOverride = modelPrefs.modelOverride
        if let forced = ModelThinkingPolicy.forcedThinkingLevelID(
            provider: textConfigForNotti.providerType, model: effectiveModelName) {
            modelPrefs.setThinkingLevelID(forced)
            nottiThinkingLevelID = forced
        }
    }

    var lockedThinkingLevelID: String? {
        ModelThinkingPolicy.forcedThinkingLevelID(
            provider: textConfigForNotti.providerType, model: effectiveModelName)
    }
    var isThinkingLocked: Bool { lockedThinkingLevelID != nil }

    func selectThinkingLevel(_ id: String) {
        guard !isThinkingLocked else { return }
        modelPrefs.setThinkingLevelID(id)
        nottiThinkingLevelID = id
    }

    let aiService: any NottiAIServing
    let repository: any NottiConversationCoordinating
    let settingsStore: AppSettingsPersisting
    let recordManager: RecordManager?
    let calendarManager: CalendarManager?
    let folderTagManager: FolderTagManager?
    private let recordRecall: NottiRecordRecall
    private let semanticEngine: SemanticSearchEngine?
    private let memoryCoordinator: NottiMemoryCoordinator

    var recordsProvider: (() -> [NoteRecord])?
    private var loadedFromHistoryID: UUID?
    private var currentConversationId: UUID = UUID()
    private var roundCount: Int { messages.count / 2 }
    private var titleGenerated = false
    private var didWarmUpSemantic = false

    init(
        aiService: any NottiAIServing = NottiAIServiceFactory.makeDefault(),
        repository: any NottiConversationCoordinating = NottiConversationRepository.live,
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live,
        recordManager: RecordManager? = nil,
        calendarManager: CalendarManager? = nil,
        folderTagManager: FolderTagManager? = nil,
        searchEngine: SemanticSearching? = nil,
        memoryCoordinator: NottiMemoryCoordinator = .live,
        anchorCount: Int = 15
    ) {
        self.aiService = aiService
        self.repository = repository
        self.settingsStore = settingsStore
        self.recordManager = recordManager
        self.calendarManager = calendarManager
        self.folderTagManager = folderTagManager
        self.memoryCoordinator = memoryCoordinator
        let engine = searchEngine ?? SemanticSearchEngine.liveForNotti(settingsStore: settingsStore)
        self.recordRecall = NottiRecordRecall(engine: engine, anchorCount: anchorCount)
        self.semanticEngine = engine as? SemanticSearchEngine
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
        hasSeenPrivacyNotice = settingsStore.loadInt(
            forKey: UDK.nottiMemoryPrivacyNoticeVersion,
            defaultValue: 0
        ) >= NottiMemoryCoordinator.currentPrivacyNoticeVersion
    }

    func markPrivacyNoticeSeen() {
        settingsStore.saveInt(
            NottiMemoryCoordinator.currentPrivacyNoticeVersion,
            forKey: UDK.nottiMemoryPrivacyNoticeVersion
        )
        hasSeenPrivacyNotice = true
    }

    func warmUpSemanticIndex() async {
        guard !didWarmUpSemantic else { return }
        didWarmUpSemantic = true
        let recs = (recordsProvider?() ?? []).filter { !$0.isDeleted }
        await recordRecall.engine.backfill(records: recs)
    }

    // MARK: - Greeting persistence

    private func loadGreeting() {
        let emoji = settingsStore.loadString(forKey: "notti_greeting_emoji", defaultValue: "")
        let text = settingsStore.loadString(forKey: "notti_greeting_text", defaultValue: "")
        if emoji.isEmpty || text.isEmpty {
            refreshGreeting()
        }
    }

    func refreshGreeting() {
        let g = GreetingPhrase.random()
        settingsStore.saveString(g.emoji, forKey: "notti_greeting_emoji")
        settingsStore.saveString(g.text, forKey: "notti_greeting_text")
    }

    var greetingEmoji: String { settingsStore.loadString(forKey: "notti_greeting_emoji", defaultValue: "👋") }
    var greetingText: String {
        let saved = settingsStore.loadString(forKey: "notti_greeting_text", defaultValue: "")
        return saved.isEmpty ? String(localized: "嗨") : saved
    }

    // MARK: - Send Message

    func sendMessage() {
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, state != .loading else { return }

        if NottiAIService.containsInjectionPattern(t) {
            injectionWarning = String(localized: "输入包含不安全的指令，请修改后重试")
            return
        }
        injectionWarning = nil

        if NottiTierLimits.sessionRoundLimitReached(currentRounds: roundCount) {
            sessionLimitReached = true
            return
        }

        inputText = ""; state = .loading
        // Clear any leftover Agent run state. The timeline popover shows whenever
        // `state == .loading && (currentToolName != nil || !agentActions.isEmpty)`,
        // so stale actions from a previous Agent task would otherwise resurface
        // during a plain-chat reply (until it finishes and state flips to .loaded).
        agentActions = []
        currentToolName = nil
        let userMsg = ChatMessage(role: .user, content: t)
        messages.append(userMsg)
        currentResponseTask = Task { await processQuestion(t, userMsg) }
    }

    func cancelResponse() {
        resolveDestructiveConfirmation(confirmed: false)
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

        let allRecs = recordsProvider?() ?? []
        let previousAssistant = messages.dropLast().last(where: { $0.role == .assistant })
        let pinnedRecordIDs = Self.computePinnedRecordIDs(
            previousAssistant: previousAssistant,
            allRecords: allRecs
        )

        let aid = UUID()
        messages.append(ChatMessage(id: aid, role: .assistant, content: ""))

        do {
            let recall = await recordRecall.recall(query: q, from: allRecs)
            let memoryRecall = await memoryCoordinator.recall(for: q)
            let recentRounds = buildRecentRounds()
            let upcoming = calendarManager?.allEvents ?? []

            let (full, tokens) = try await withCheckedThrowingContinuation { cont in
                let service = aiService
                let r = recall
                let rounds = recentRounds
                let question = q
                let events = upcoming
                let pinned = pinnedRecordIDs
                let memories = memoryRecall
                Task.detached {
                    do {
                        let result = try await NottiMemoryPromptContext.$recall.withValue(memories) {
                            try await service.ask(
                                question: question,
                                recall: r,
                                recentRounds: rounds,
                                upcomingEvents: events,
                                pinnedRecordIDs: pinned
                            )
                        }
                        cont.resume(returning: result)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            aiService.accumulatePublic(tokens)

            let promptRecords = recall.records
            let (clean, cits) = await Task.detached {
                let visible = NottiAIService.stripThinkTags(full)
                let cits = NottiAIService.mapCitations(from: visible, records: promptRecords)
                let cleanStripped = NottiAIService.stripCitationMarkers(visible)
                return (cleanStripped, cits)
            }.value

            if Task.isCancelled { return }

            // Update UI
            if let idx = messages.firstIndex(where: { $0.id == aid }) {
                messages[idx] = ChatMessage(id: aid, role: .assistant, content: clean, citations: cits)
            }
            state = .loaded

            if !isAgentModeEnabled, NottiIntentDetector.looksLikeActionRequest(q) {
                agentSuggestionMessageID = aid
                lastUserQuestion = q
            } else {
                agentSuggestionMessageID = nil
            }

            Task { [memoryCoordinator] in
                await memoryCoordinator.recordSuccessfulRound(
                    userMessageID: userMsg.id,
                    userMessage: q,
                    injectedMemoryIDs: memoryRecall.memoryIDs
                )
            }

            // Title + save (always upsert, no loadedFromHistoryID guard)
            Task {
                await generateAndSyncTitle()
                saveToHistory()
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
        let draft = NottiConversationDraft(
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

    private static func computePinnedRecordIDs(
        previousAssistant: ChatMessage?,
        allRecords: [NoteRecord]
    ) -> [UUID] {
        guard let previousAssistant, !previousAssistant.citations.isEmpty else { return [] }
        let validIDs = Set(
            allRecords
                .filter { !$0.isDeleted && !$0.isEncrypted }
                .map(\.id)
        )
        return previousAssistant.citations.map(\.recordID).filter { validIDs.contains($0) }
    }

    // MARK: - Title

    private static let modelNameKeywords: Set<String> = [
        "deepseek", "qwen", "gpt", "claude", "chatgpt", "openai", "anthropic",
        "minimax", "glm", "ernie", "notti", "doubao", "gemini", "llama",
        "通义", "千问", "文心", "一言", "智谱", "豆包", "星火",
    ]

    private static let titleTriggerRoundCount = 1

    private func generateAndSyncTitle() async {
        guard !titleGenerated else { return }
        guard let first = messages.first(where: { $0.role == .user })?.content,
              !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if currentTitle == "Notti" || currentTitle == String(localized: "新对话") {
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
        resolveDestructiveConfirmation(confirmed: false)
        guard !messages.isEmpty else { currentQuestions = randomQuestions(); return }

        let msgs = messages
        let title = currentTitle
        let convId = currentConversationId

        Task.detached(priority: .utility) { [repository] in
            try? repository.upsertHistory(from: msgs, id: convId, title: title)
        }

        sessionLimitReached = false
        messages = []
        try? repository.clearDraft()
        state = .idle; inputText = ""
        currentQuestions = randomQuestions()
        refreshGreeting()
        currentTitle = "Notti"
        isGeneratingTitle = false
        titleGenerated = false
        loadedFromHistoryID = nil
        currentConversationId = UUID()
    }

    func loadConversation(_ saved: SavedConversation) {
        resolveDestructiveConfirmation(confirmed: false)
        messages = saved.messages
        state = .idle
        loadedFromHistoryID = saved.id
        currentTitle = saved.title
        currentConversationId = saved.id
        titleGenerated = true
        isGeneratingTitle = false

        let draft = NottiConversationDraft(id: saved.id, title: saved.title, messages: saved.messages)
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

        if NottiAIService.containsInjectionPattern(t) {
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

        let searchEngine = SemanticSearchEngine.liveForNotti(settingsStore: settingsStore)

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
            MemorySearchTool(coordinator: memoryCoordinator),
            MemoryForgetTool(repository: NottiMemoryRepository.live),
            WebFetchTool(),
            WebSearchTool(settingsStore: settingsStore),
            NoteDeleteTool(recordManager: recordManager),
            TodoDeleteTool(recordManager: recordManager),
            ScheduleDeleteTool(calendarManager: calendarManager)
        ]
        let registry = AgentToolRegistry(tools: tools)
        let trustManager = AgentTrustManager(settingsStore: settingsStore)
        let actionStore = AgentActionStore()
        return AgentExecutor(
            aiService: aiService,
            toolRegistry: registry,
            actionStore: actionStore,
            trustManager: trustManager,
            confirmDestructiveAction: { [weak self] toolName, parameters in
                guard let self else { return false }
                return await self.requestDestructiveConfirmation(
                    toolName: toolName,
                    parameters: parameters
                )
            }
        )
    }

    private func requestDestructiveConfirmation(
        toolName: String,
        parameters: [String: Any]
    ) async -> Bool {
        resolveDestructiveConfirmation(confirmed: false)
        let detail = AgentToolPresentation.forName(toolName).displayName
        return await withCheckedContinuation { continuation in
            destructiveConfirmationContinuation = continuation
            pendingDestructiveConfirmation = NottiDestructiveConfirmation(
                toolName: toolName,
                detail: detail
            )
        }
    }

    func resolveDestructiveConfirmation(confirmed: Bool) {
        let continuation = destructiveConfirmationContinuation
        destructiveConfirmationContinuation = nil
        pendingDestructiveConfirmation = nil
        continuation?.resume(returning: confirmed)
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
            let (text, confirmedToolSummary, _, usedMemoryIDs) = try await executor.run(
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

            messages.append(ChatMessage(role: .assistant, content: NottiAIService.stripThinkTags(text)))
            state = .loaded
            saveCurrentDraft()
            if let userMessageID = messages.last(where: { $0.role == .user })?.id {
                Task { [memoryCoordinator] in
                    await memoryCoordinator.recordSuccessfulRound(
                        userMessageID: userMessageID,
                        userMessage: question,
                        confirmedToolResults: confirmedToolSummary.isEmpty ? [] : [confirmedToolSummary],
                        injectedMemoryIDs: usedMemoryIDs
                    )
                }
            }
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
