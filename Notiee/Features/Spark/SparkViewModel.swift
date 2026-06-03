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

    let aiService: SparkAIService
    let conversationStore: SparkConversationPersisting
    let historyStore: SparkHistoryPersisting
    let settingsStore: AppSettingsPersisting

    var recordsProvider: (() -> [NoteRecord])?
    private var loadedFromHistoryID: UUID?

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
        loadHistory()
        checkPrivacyNotice()
        loadGreeting()
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
    var greetingText: String { settingsStore.loadString(forKey: "spark_greeting_text", defaultValue: "嗨") }

    private func loadHistory() {
        guard let rounds = try? conversationStore.loadConversations() else { return }
        var msgs: [ChatMessage] = []
        for r in rounds { msgs.append(r.userMessage); msgs.append(r.assistantMessage) }
        self.messages = msgs
        if msgs.isEmpty { currentQuestions = randomQuestions() }
    }

    func sendMessage() {
        let t = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, state != .loading else { return }
        inputText = ""; state = .loading
        let userMsg = ChatMessage(role: .user, content: t)
        messages.append(userMsg)
        Task { await processQuestion(t, userMsg) }
    }

    func sendQuestion(_ q: String) { inputText = q; sendMessage() }

    /// Called by exyte/Chat's didSendMessage closure with a DraftMessage.
    }

    private func processQuestion(_ q: String, _ userMsg: ChatMessage) async {
        if !NetworkMonitor.shared.isConnected {
            messages.append(ChatMessage(role: .assistant, content: "网络不可用，无法进行 AI 问答。请检查网络后重试。"))
            state = .offline; saveCurrentConversation(); return
        }
        let aid = UUID()
        // Empty content triggers "thinking..." animation in SparkChatBubble
        messages.append(ChatMessage(id: aid, role: .assistant, content: ""))
        do {
            let allRecs = recordsProvider?() ?? []
            let stream = aiService.askStreaming(question: q, with: allRecs)
            var full = ""
            for try await chunk in stream {
                full += chunk
                if let idx = messages.firstIndex(where: { $0.id == aid }) {
                    messages[idx] = ChatMessage(id: aid, role: .assistant, content: full)
                }
            }
            let (clean, newMem) = aiService.extractMemory(from: full)
            for (k, v) in newMem { let ms = SparkMemoryStore.live; ms.set(k, value: v) }
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
            updateTitle()
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == aid }) { messages.remove(at: idx) }
            messages.append(ChatMessage(role: .assistant, content: "抱歉，出错了：\(error.localizedDescription)"))
            state = .error(error.localizedDescription)
        }
        saveCurrentConversation()
    }

    private func saveCurrentConversation() {
        var rounds: [ConversationRound] = []; var i = 0
        while i + 1 < messages.count {
            if messages[i].role == .user, messages[i+1].role == .assistant {
                rounds.append(ConversationRound(userMessage: messages[i], assistantMessage: messages[i+1]))
                i += 2
            } else { i += 1 }
        }
        try? conversationStore.saveConversations(rounds)
    }

    private func updateTitle() {
        guard let first = messages.first(where: {$0.role == .user}) else {
            settingsStore.saveString("Spark", forKey: "spark_current_title")
            return
        }
        let t = String(first.content.prefix(15)).trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        settingsStore.saveString(t, forKey: "spark_current_title")
    }

    var currentTitle: String {
        messages.isEmpty ? "Spark" : settingsStore.loadString(forKey: "spark_current_title", defaultValue: "Spark")
    }

    // MARK: - History management (performance optimized)

    func newConversation() {
        guard !messages.isEmpty else { currentQuestions = randomQuestions(); return }
        let msgs = messages
        // Only save to history if this conversation wasn't loaded from history
        let wasLoadedFromHistory = loadedFromHistoryID != nil
        Task.detached(priority: .background) { [wasLoadedFromHistory] in
            guard !wasLoadedFromHistory else { return }
            let title = msgs.first(where: { $0.role == .user })?.content ?? "对话"
            let s = SavedConversation(title: String(title.prefix(30)), createdAt: msgs.first?.timestamp ?? Date(), lastMessageAt: msgs.last?.timestamp ?? Date(), messages: msgs)
            var hist = (try? SparkHistoryStore.live.loadConversations()) ?? []
            hist.append(s); try? SparkHistoryStore.live.saveConversations(hist)
        }
        messages = []; try? conversationStore.saveConversations([])
        state = .idle; inputText = ""
        currentQuestions = randomQuestions()
        refreshGreeting()
        settingsStore.saveString("Spark", forKey: "spark_current_title")
        loadedFromHistoryID = nil
    }

    func loadConversation(_ saved: SavedConversation) {
        state = .loading
        let msgs = saved.messages
        Task {
            await MainActor.run {
                self.messages = msgs
                self.state = .idle
                self.loadedFromHistoryID = saved.id
                self.updateTitle()
            }
            saveCurrentConversation()
        }
    }

    func deleteConversations(_ ids: Set<UUID>) {
        var hist = (try? historyStore.loadConversations()) ?? []
        hist.removeAll { ids.contains($0.id) }
        try? historyStore.saveConversations(hist)
    }
}
