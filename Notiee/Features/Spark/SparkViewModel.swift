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

    let aiService: SparkAIService
    let conversationStore: SparkConversationPersisting
    let historyStore: SparkHistoryPersisting
    let settingsStore: AppSettingsPersisting

    var recordsProvider: (() -> [NoteRecord])?
    private var loadedFromHistoryID: UUID?
    private var currentConversationId: UUID = UUID()
    private var roundCount: Int { messages.count / 2 }
    private var titleGenerated = false

    init(
        aiService: SparkAIService = SparkAIService(),
        conversationStore: SparkConversationPersisting = SparkConversationStore.live,
        historyStore: SparkHistoryPersisting = SparkHistoryStore.live,
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live
    ) {
        self.aiService = aiService
        self.conversationStore = conversationStore
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        migrateConversationToHistory()
        checkPrivacyNotice()
        loadGreeting()
    }

    private func migrateConversationToHistory() {
        guard let rounds = try? conversationStore.loadConversations(), !rounds.isEmpty else { return }
        var msgs: [ChatMessage] = []
        for r in rounds { msgs.append(r.userMessage); msgs.append(r.assistantMessage) }

        let savedConvID: UUID? = {
            guard let str = UserDefaults.standard.string(forKey: UDK.sparkCurrentConversationId),
                  let id = UUID(uuidString: str) else { return nil }
            return id
        }()

        if let savedID = savedConvID,
           var hist = try? historyStore.loadConversations(),
           let idx = hist.firstIndex(where: { $0.id == savedID }) {
            hist[idx].messages = msgs
            hist[idx].lastMessageAt = msgs.last?.timestamp ?? Date()
            hist.sort { $0.lastMessageAt > $1.lastMessageAt }
            try? historyStore.saveConversations(hist)
        } else {
            let title = String(msgs.first?.content.prefix(15) ?? "Spark").trimmingCharacters(in: .whitespaces)
            let saved = SavedConversation(
                id: savedConvID ?? UUID(),
                title: title.isEmpty ? "Spark" : title,
                createdAt: msgs.first?.timestamp ?? Date(),
                lastMessageAt: msgs.last?.timestamp ?? Date(),
                messages: msgs
            )
            var hist = (try? historyStore.loadConversations()) ?? []
            hist.append(saved)
            hist.sort { $0.lastMessageAt > $1.lastMessageAt }
            try? historyStore.saveConversations(hist)
        }

        UserDefaults.standard.removeObject(forKey: UDK.sparkCurrentConversationId)
        try? conversationStore.saveConversations([])
    }

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
        Task { await processQuestion(t, userMsg) }
    }

    func sendQuestion(_ q: String) { inputText = q; sendMessage() }

    private func processQuestion(_ q: String, _ userMsg: ChatMessage) async {
        if !NetworkMonitor.shared.isConnected {
            messages.append(ChatMessage(role: .assistant, content: String(localized: "网络不可用，无法进行 AI 问答。请检查网络后重试。")))
            state = .offline; saveCurrentConversation(); return
        }
        let aid = UUID()
        messages.append(ChatMessage(id: aid, role: .assistant, content: ""))
        do {
            let allRecs = recordsProvider?() ?? []
            let recentRounds = buildRecentRounds()
            let stream = aiService.askStreaming(question: q, with: allRecs, recentRounds: recentRounds)
            var full = ""
            for try await chunk in stream {
                full += chunk
                if let idx = messages.firstIndex(where: { $0.id == aid }) {
                    messages[idx] = ChatMessage(id: aid, role: .assistant, content: full)
                }
            }
            let (clean, ops) = aiService.extractMemory(from: full)
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
            let all = allRecs.filter{!$0.isDeleted}.sorted{$0.capturedAt>$1.capturedAt}
            let cIdx = aiService.extractCitations(from: clean, recordCount: all.count)
            let cits: [Citation] = cIdx.compactMap { idx in
                guard idx < all.count else { return nil }
                let r = all[idx]; return Citation(recordID: r.id, title: r.title, capturedAt: r.capturedAt)
            }
            if let idx = messages.firstIndex(where: { $0.id == aid }) {
                messages[idx] = ChatMessage(id: aid, role: .assistant, content: clean, citations: cits)
            }
            state = .loaded

            if loadedFromHistoryID == nil {
                Task { await generateAndSyncTitle(); saveToHistory() }
            }

            triggerMemoryCompressionIfNeeded()
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == aid }) { messages.remove(at: idx) }
            messages.append(ChatMessage(role: .assistant, content: "抱歉，出错了：\(error.localizedDescription)"))
            state = .error(error.localizedDescription)
        }
        saveCurrentConversation()
    }

    private func saveCurrentConversation() {
        let msgs = messages
        let store = conversationStore
        Task.detached(priority: .background) {
            var rounds: [ConversationRound] = []; var i = 0
            while i + 1 < msgs.count {
                if msgs[i].role == .user, msgs[i+1].role == .assistant {
                    rounds.append(ConversationRound(userMessage: msgs[i], assistantMessage: msgs[i+1]))
                    i += 2
                } else { i += 1 }
            }
            try? store.saveConversations(rounds)
        }
    }

    // MARK: - Memory Compression

    private func buildRecentRounds() -> [ConversationRound] {
        var rounds: [ConversationRound] = []
        var i = 0
        let msgs = messages
        while i + 1 < msgs.count {
            if msgs[i].role == .user, msgs[i+1].role == .assistant {
                rounds.append(ConversationRound(userMessage: msgs[i], assistantMessage: msgs[i+1]))
                i += 2
            } else { i += 1 }
        }
        return rounds
    }

    private func triggerMemoryCompressionIfNeeded() {
        guard roundCount >= SparkAIService.memoryTriggerRoundCount else { return }
        let msgs = messages
        let service = aiService
        let store = conversationStore
        Task.detached(priority: .background) {
            let rounds = await Self.buildRounds(from: msgs)
            let lastCompressed = UserDefaults.standard.integer(forKey: UDK.sparkLastMemoryCompressionRounds)
            guard rounds.count > lastCompressed else { return }
            await service.compressMemory(from: rounds)
            UserDefaults.standard.set(rounds.count, forKey: UDK.sparkLastMemoryCompressionRounds)
        }
    }

    private static func buildRounds(from msgs: [ChatMessage]) -> [ConversationRound] {
        var rounds: [ConversationRound] = []; var i = 0
        while i + 1 < msgs.count {
            if msgs[i].role == .user, msgs[i+1].role == .assistant {
                rounds.append(ConversationRound(userMessage: msgs[i], assistantMessage: msgs[i+1]))
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

    private func generateAndSyncTitle() async {
        guard !titleGenerated else { return }
        titleGenerated = true
        guard let first = messages.first(where: { $0.role == .user })?.content,
              !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGeneratingTitle = true

        if let neutralTitle = clientSideTitle(from: first) {
            currentTitle = neutralTitle
            isGeneratingTitle = false
            return
        }

        do {
            let title = try await aiService.generateTitle(for: first)
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || containsModelName(trimmed) {
                fallbackTitle(from: first)
            } else {
                currentTitle = trimmed
            }
        } catch {
            fallbackTitle(from: first)
        }
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
        let t = String(firstMessage.trimmingCharacters(in: .whitespacesAndNewlines).prefix(15))
        currentTitle = t.isEmpty ? String(localized: "新对话") : t
    }

    private func saveToHistory() {
        guard loadedFromHistoryID == nil else { return }
        let msgs = messages
        let id = currentConversationId
        let title = currentTitle
        UserDefaults.standard.set(id.uuidString, forKey: UDK.sparkCurrentConversationId)
        Task.detached(priority: .background) {
            var hist = (try? SparkHistoryStore.live.loadConversations()) ?? []
            if let idx = hist.firstIndex(where: { $0.id == id }) {
                hist[idx].messages = msgs
                hist[idx].lastMessageAt = msgs.last?.timestamp ?? Date()
                if !title.isEmpty && title != "Spark" {
                    hist[idx].title = title
                }
            } else {
                guard let firstMsg = msgs.first else { return }
                let s = SavedConversation(
                    id: id,
                    title: title,
                    createdAt: firstMsg.timestamp,
                    lastMessageAt: msgs.last?.timestamp ?? Date(),
                    messages: msgs
                )
                hist.append(s)
            }
            hist.sort { $0.lastMessageAt > $1.lastMessageAt }
            try? SparkHistoryStore.live.saveConversations(hist)
        }
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
        let wasLoadedFromHistory = loadedFromHistoryID != nil
        let title = currentTitle
        let convId = currentConversationId
        Task.detached(priority: .background) { [wasLoadedFromHistory] in
            guard !wasLoadedFromHistory else { return }
            let s = SavedConversation(
                id: convId,
                title: title,
                createdAt: msgs.first?.timestamp ?? Date(),
                lastMessageAt: msgs.last?.timestamp ?? Date(),
                messages: msgs
            )
            var hist = (try? SparkHistoryStore.live.loadConversations()) ?? []
            if let idx = hist.firstIndex(where: { $0.id == convId }) {
                hist[idx] = s
            } else {
                hist.append(s)
            }
            hist.sort { $0.lastMessageAt > $1.lastMessageAt }
            try? SparkHistoryStore.live.saveConversations(hist)
        }
        messages = []; try? conversationStore.saveConversations([])
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
        let msgs = saved.messages
        self.messages = msgs
        self.state = .idle
        self.loadedFromHistoryID = saved.id
        self.currentTitle = saved.title
        self.currentConversationId = saved.id
        self.titleGenerated = true
        isGeneratingTitle = false
        saveCurrentConversation()
    }

    func deleteConversations(_ ids: Set<UUID>) {
        var hist = (try? historyStore.loadConversations()) ?? []
        hist.removeAll { ids.contains($0.id) }
        try? historyStore.saveConversations(hist)
    }
}
