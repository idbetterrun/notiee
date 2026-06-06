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

    private static let historyOpQueue = DispatchQueue(label: "com.notiee.history.ops.serial", qos: .utility)

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

        UserDefaults.standard.removeObject(forKey: UDK.sparkCurrentConversationId)
        try? conversationStore.saveConversations([])

        let fallbackConvID = currentConversationId
        Self.historyOpQueue.async {
            try? SparkHistoryStore.live.atomicUpdate { hist in
                let hc = hist.count
                Logger.spark.debug("[migrate] histCount=\(hc) savedConvID=\(String(describing: savedConvID))")
                if let savedID = savedConvID, let idx = hist.firstIndex(where: { $0.id == savedID }) {
                    Logger.spark.debug("[migrate] FOUND at idx=\(idx), updating msgCount=\(msgs.count)")
                    hist[idx].messages = msgs
                    hist[idx].lastMessageAt = msgs.last?.timestamp ?? Date()
                } else {
                    let newID = savedConvID ?? fallbackConvID
                    Logger.spark.debug("[migrate] NOT FOUND, creating new. id=\(newID)")
                    let title = String(msgs.first?.content.prefix(15) ?? "Spark").trimmingCharacters(in: .whitespaces)
                    let saved = SavedConversation(
                        id: newID,
                        title: title.isEmpty ? "Spark" : title,
                        createdAt: msgs.first?.timestamp ?? Date(),
                        lastMessageAt: msgs.last?.timestamp ?? Date(),
                        messages: msgs
                    )
                    hist.append(saved)
                    let nhc = hist.count
                    Logger.spark.debug("[migrate] appended, new histCount=\(nhc)")
                }
                hist.sort { $0.lastMessageAt > $1.lastMessageAt }
            }
        }
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
        Logger.spark.debug("[processQuestion] START round=\(self.roundCount) msgCount=\(self.messages.count)")
        if !NetworkMonitor.shared.isConnected {
            Logger.spark.debug("[processQuestion] OFFLINE, aborting")
            messages.append(ChatMessage(role: .assistant, content: String(localized: "网络不可用，无法进行 AI 问答。请检查网络后重试。")))
            state = .offline; saveCurrentConversation(); return
        }
        let aid = UUID()
        messages.append(ChatMessage(id: aid, role: .assistant, content: ""))
        do {
            let allRecs = recordsProvider?() ?? []
            let recentRounds = buildRecentRounds()
            Logger.spark.debug("[processQuestion] asking LLM via continuation+detached...")
            let (full, tokens) = try await withCheckedThrowingContinuation { cont in
                let service = aiService
                let recs = allRecs
                let rounds = recentRounds
                let question = q
                Task.detached {
                    do {
                        let result = try await service.ask(question: question, with: recs, recentRounds: rounds)
                        Logger.spark.debug("[detached] ask returned, calling cont.resume")
                        cont.resume(returning: result)
                        Logger.spark.debug("[detached] cont.resume called")
                    } catch {
                        Logger.spark.debug("[detached] ask threw, calling cont.resume(throwing:)")
                        cont.resume(throwing: error)
                        Logger.spark.debug("[detached] cont.resume(throwing:) called")
                    }
                }
            }
            Logger.spark.debug("[processQuestion] STEP1 ask returned, len=\(full.count) tokens=\(tokens)")
            aiService.accumulatePublic(tokens)

            Logger.spark.debug("[processQuestion] STEP2 calling extractMemory...")
            let (clean, ops) = aiService.extractMemory(from: full)
            Logger.spark.debug("[processQuestion] STEP2 done, s=\(ops.toSet.count) u=\(ops.toUpdate.count) d=\(ops.toDelete.count)")

            let ms = SparkMemoryStore.live
            Logger.spark.debug("[processQuestion] STEP3 memory ops loop start")
            var memoryCount = 0
            for (k, v) in ops.toSet { ms.set(k, value: v); memoryCount += 1 }
            for (k, v) in ops.toUpdate { ms.set(k, value: v); memoryCount += 1 }
            for k in ops.toDelete { ms.delete(k); memoryCount += 1 }
            Logger.spark.debug("[processQuestion] STEP3 memory ops done count=\(memoryCount)")

            if memoryCount > 0 {
                Logger.spark.debug("[processQuestion] STEP4 showing memory toast")
                withAnimation(.easeInOut) { memoryActionText = String(localized: "✓ 已记忆") }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    withAnimation(.easeInOut) {
                        if memoryActionText == String(localized: "✓ 已记忆") { memoryActionText = nil }
                    }
                }
            }

            Logger.spark.debug("[processQuestion] STEP5 filter+sort records")
            let all = allRecs.filter{!$0.isDeleted}.sorted{$0.capturedAt>$1.capturedAt}
            Logger.spark.debug("[processQuestion] STEP5 done recs=\(all.count)")

            Logger.spark.debug("[processQuestion] STEP6 extractCitations regex")
            var cIdx = aiService.extractCitations(from: clean, recordCount: all.count)

            if cIdx.isEmpty {
                Logger.spark.debug("[processQuestion] STEP6 fallback fuzzy match")
                cIdx = aiService.extractCitationsFallback(from: clean, records: all)
            }
            Logger.spark.debug("[processQuestion] STEP6 done cIdx=\(cIdx.count)")

            Logger.spark.debug("[processQuestion] STEP7 build Citation array")
            let cits: [Citation] = cIdx.compactMap { idx in
                guard idx < all.count else { return nil }
                let r = all[idx]; return Citation(recordID: r.id, title: r.title, capturedAt: r.capturedAt)
            }
            Logger.spark.debug("[processQuestion] STEP7 done citCount=\(cits.count)")

            Logger.spark.debug("[processQuestion] STEP8 messages[idx] = ChatMessage with citations...")
            if let idx = messages.firstIndex(where: { $0.id == aid }) {
                messages[idx] = ChatMessage(id: aid, role: .assistant, content: clean, citations: cits)
                Logger.spark.debug("[processQuestion] STEP8 message updated OK, cit=\(cits.count)")
            }
            Logger.spark.debug("[processQuestion] STEP9 state = .loaded")
            state = .loaded
            Logger.spark.debug("[processQuestion] STEP9 done")

            if loadedFromHistoryID == nil {
                Logger.spark.debug("[processQuestion] STEP10 dispatching title+save task")
                Task {
                    await generateAndSyncTitle()
                    saveToHistory()
                }
            }

            Logger.spark.debug("[processQuestion] STEP11 memory compression check")
            triggerMemoryCompressionIfNeeded()

            Logger.spark.debug("[processQuestion] STEP12 personal info check")
            if SparkAIService.containsPersonalInfoPattern(q) {
                Logger.spark.debug("[processQuestion] STEP12 triggered memory pipeline")
                triggerMemoryPipeline(userMessage: q, assistantResponse: clean)
            }
            Logger.spark.debug("[processQuestion] STEP13 DONE exiting do block")
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == aid }) { messages.remove(at: idx) }
            messages.append(ChatMessage(role: .assistant, content: "抱歉，出错了：\(error.localizedDescription)"))
            state = .error(error.localizedDescription)
        }
        Logger.spark.debug("[processQuestion] STEP14 saveCurrentConversation dispatching")
        saveCurrentConversation()
        Logger.spark.debug("[processQuestion] EXIT method")
    }

    private func saveCurrentConversation() {
        let msgs = messages
        Logger.spark.debug("[saveCurrentConversation] dispatching detached task, msgCount=\(msgs.count)")
        Task.detached(priority: .background) {
            var rounds: [ConversationRound] = []; var i = 0
            while i + 1 < msgs.count {
                if msgs[i].role == .user, msgs[i+1].role == .assistant {
                    rounds.append(ConversationRound(userMessage: msgs[i], assistantMessage: msgs[i+1]))
                    i += 2
                } else { i += 1 }
            }
            try? SparkConversationStore.live.saveConversations(rounds)
        }
    }

    // MARK: - Memory Pipeline (implicit extraction via lightweight LLM)

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

    private static let titleTriggerRoundCount = 3

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
        } catch {
            // keep current fallback title
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
        guard loadedFromHistoryID == nil else { Logger.spark.debug("[saveToHistory] skipped (loaded from history)"); return }
        let msgs = messages
        let id = currentConversationId
        let title = currentTitle
        Logger.spark.debug("[saveToHistory] dispatching via historyOpQueue, id=\(id) msgCount=\(msgs.count) title=\(title)")
        UserDefaults.standard.set(id.uuidString, forKey: UDK.sparkCurrentConversationId)

        Self.historyOpQueue.async {
            try? SparkHistoryStore.live.atomicUpdate { hist in
                let hc = hist.count
                Logger.spark.debug("[saveToHistory] histCount=\(hc) searching for id=\(id)")
                if let idx = hist.firstIndex(where: { $0.id == id }) {
                    Logger.spark.debug("[saveToHistory] FOUND at idx=\(idx), updating msgCount=\(msgs.count)")
                    hist[idx].messages = msgs
                    hist[idx].lastMessageAt = msgs.last?.timestamp ?? Date()
                    if !title.isEmpty && title != "Spark" {
                        hist[idx].title = title
                    }
                } else {
                    Logger.spark.debug("[saveToHistory] NOT FOUND, creating new entry. id=\(id)")
                    for (i, entry) in hist.enumerated() {
                        Logger.spark.debug("[saveToHistory]   hist[\(i)].id=\(entry.id) title=\(entry.title)")
                    }
                    guard let firstMsg = msgs.first else { return }
                    let s = SavedConversation(
                        id: id,
                        title: title,
                        createdAt: firstMsg.timestamp,
                        lastMessageAt: msgs.last?.timestamp ?? Date(),
                        messages: msgs
                    )
                    hist.append(s)
                    let nhc = hist.count
                    Logger.spark.debug("[saveToHistory] appended new entry, new histCount=\(nhc)")
                }
                hist.sort { $0.lastMessageAt > $1.lastMessageAt }
            }
            Logger.spark.debug("[saveToHistory] historyOpQueue COMPLETE, id=\(id)")
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

        if !wasLoadedFromHistory {
            Self.historyOpQueue.async {
                try? SparkHistoryStore.live.atomicUpdate { hist in
                    let s = SavedConversation(
                        id: convId,
                        title: title,
                        createdAt: msgs.first?.timestamp ?? Date(),
                        lastMessageAt: msgs.last?.timestamp ?? Date(),
                        messages: msgs
                    )
                    if let idx = hist.firstIndex(where: { $0.id == convId }) {
                        hist[idx] = s
                    } else {
                        hist.append(s)
                    }
                    hist.sort { $0.lastMessageAt > $1.lastMessageAt }
                }
            }
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
        Self.historyOpQueue.async {
            try? SparkHistoryStore.live.atomicUpdate { hist in
                hist.removeAll { ids.contains($0.id) }
            }
        }
    }
}
