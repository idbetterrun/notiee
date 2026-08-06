import Combine
import Foundation

enum NewUIPreviewNottiRole: Equatable {
    case user
    case assistant
}

struct NewUIPreviewNottiMessage: Identifiable, Equatable {
    let id: UUID
    let role: NewUIPreviewNottiRole
    var content: String
    var isComplete: Bool

    init(
        id: UUID = UUID(),
        role: NewUIPreviewNottiRole,
        content: String,
        isComplete: Bool = true
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.isComplete = isComplete
    }
}

struct NewUIPreviewNottiModel: Identifiable, Equatable {
    let id: String
    let title: String
}

enum NewUIPreviewNottiThinking: String, CaseIterable, Identifiable {
    case quick
    case balanced
    case deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return String(localized: "快速")
        case .balanced: return String(localized: "均衡")
        case .deep: return String(localized: "深入")
        }
    }
}

struct NewUIPreviewNottiConversation: Identifiable, Equatable {
    let id: UUID
    let title: String
    let messages: [NewUIPreviewNottiMessage]
}

@MainActor
final class NewUIPreviewNottiState: ObservableObject {
    @Published var inputText = ""
    @Published private(set) var messages: [NewUIPreviewNottiMessage] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var conversationTitle = "Notti"
    @Published var selectedThinking: NewUIPreviewNottiThinking = .quick
    @Published var webSearchEnabled = false
    @Published var agentModeEnabled = false
    @Published private(set) var selectedModelID: String

    let modelOptions: [NewUIPreviewNottiModel]
    let promptShortcuts: [String] = [
        String(localized: "分析洞察"),
        String(localized: "记录复盘"),
        String(localized: "待办规划")
    ]

    private var pendingChunks: [String] = []
    private var streamingMessageID: UUID?
    private var streamTask: Task<Void, Never>?

    init(modelOptions: [NewUIPreviewNottiModel]? = nil) {
        let resolvedModels = modelOptions ?? NewUIPreviewNottiState.defaultModelOptions
        self.modelOptions = resolvedModels
        self.selectedModelID = resolvedModels.first?.id ?? "preview-model"
    }

    var selectedModelTitle: String {
        modelOptions.first(where: { $0.id == selectedModelID })?.title
            ?? String(localized: "模型")
    }

    var savedConversations: [NewUIPreviewNottiConversation] {
        [
            NewUIPreviewNottiConversation(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
                title: String(localized: "发布复盘"),
                messages: [
                    NewUIPreviewNottiMessage(
                        id: UUID(uuidString: "51000000-0000-0000-0000-000000000001")!,
                        role: .user,
                        content: String(localized: "帮我复盘最近的产品记录")
                    ),
                    NewUIPreviewNottiMessage(
                        id: UUID(uuidString: "51000000-0000-0000-0000-000000000002")!,
                        role: .assistant,
                        content: Self.completedResponse
                    )
                ]
            ),
            NewUIPreviewNottiConversation(
                id: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
                title: String(localized: "本周待办"),
                messages: [
                    NewUIPreviewNottiMessage(
                        id: UUID(uuidString: "52000000-0000-0000-0000-000000000001")!,
                        role: .user,
                        content: String(localized: "整理一下本周还没完成的事情")
                    ),
                    NewUIPreviewNottiMessage(
                        id: UUID(uuidString: "52000000-0000-0000-0000-000000000002")!,
                        role: .assistant,
                        content: String(localized: "你还有三件需要关注的事：整理路线图、发送会议纪要，以及补充界面草图。")
                    )
                ]
            )
        ]
    }

    func selectModel(_ id: String) {
        guard modelOptions.contains(where: { $0.id == id }) else { return }
        selectedModelID = id
    }

    func submit(
        prompt: String? = nil,
        reduceMotion: Bool = false,
        startsStreaming: Bool = true
    ) {
        let submitted = (prompt ?? inputText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty, !isGenerating else { return }

        inputText = ""
        messages.append(NewUIPreviewNottiMessage(role: .user, content: submitted))
        if messages.filter({ $0.role == .user }).count == 1 {
            conversationTitle = Self.title(from: submitted)
        }
        beginAssistantResponse(reduceMotion: reduceMotion, startsStreaming: startsStreaming)
    }

    func stopGenerating() {
        streamTask?.cancel()
        streamTask = nil
        pendingChunks.removeAll()
        isGenerating = false

        guard let id = streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == id }) else {
            streamingMessageID = nil
            return
        }
        if messages[index].content.isEmpty {
            messages.remove(at: index)
        } else {
            messages[index].isComplete = true
        }
        streamingMessageID = nil
    }

    func regenerate(reduceMotion: Bool = false, startsStreaming: Bool = true) {
        guard !isGenerating,
              let assistantIndex = messages.lastIndex(where: { $0.role == .assistant }),
              messages[..<assistantIndex].last(where: { $0.role == .user }) != nil else { return }

        messages.remove(at: assistantIndex)
        beginAssistantResponse(reduceMotion: reduceMotion, startsStreaming: startsStreaming)
    }

    func newConversation() {
        stopGenerating()
        messages.removeAll()
        inputText = ""
        conversationTitle = "Notti"
        webSearchEnabled = false
        agentModeEnabled = false
        selectedThinking = .quick
    }

    func loadConversation(_ conversation: NewUIPreviewNottiConversation) {
        stopGenerating()
        messages = conversation.messages
        conversationTitle = conversation.title
        inputText = ""
        webSearchEnabled = false
        agentModeEnabled = false
    }

    @discardableResult
    func revealNextChunk() -> Bool {
        guard isGenerating,
              let id = streamingMessageID,
              let index = messages.firstIndex(where: { $0.id == id }) else { return false }

        guard !pendingChunks.isEmpty else {
            finishStreamingMessage(at: index)
            return false
        }

        messages[index].content += pendingChunks.removeFirst()
        if pendingChunks.isEmpty {
            finishStreamingMessage(at: index)
        }
        return true
    }

    func revealAllPending() {
        streamTask?.cancel()
        streamTask = nil
        while revealNextChunk() {}
    }

    private func beginAssistantResponse(reduceMotion: Bool, startsStreaming: Bool) {
        streamTask?.cancel()

        let usesWebSearch = webSearchEnabled
        webSearchEnabled = false
        let message = NewUIPreviewNottiMessage(role: .assistant, content: "", isComplete: false)
        messages.append(message)
        streamingMessageID = message.id
        pendingChunks = Self.responseChunks(
            usesWebSearch: usesWebSearch,
            usesAgent: agentModeEnabled,
            reduceMotion: reduceMotion
        )
        isGenerating = true

        guard startsStreaming else { return }
        let delay: UInt64 = reduceMotion ? 140_000_000 : 48_000_000
        streamTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, self?.revealNextChunk() == true {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    return
                }
            }
        }
    }

    private func finishStreamingMessage(at index: Int) {
        messages[index].isComplete = true
        isGenerating = false
        streamingMessageID = nil
        streamTask = nil
    }

    private static func title(from prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        return String(firstLine.prefix(14))
    }

    private static func responseChunks(
        usesWebSearch: Bool,
        usesAgent: Bool,
        reduceMotion: Bool
    ) -> [String] {
        var chunks: [String] = []
        if usesWebSearch {
            chunks.append(String(localized: "**已联网检索（演示）**\n\n"))
        }
        if usesAgent {
            chunks.append(String(localized: "**Agent 已规划本次回答（演示）**\n\n"))
        }

        let body = [
            String(localized: "我先把最近的记录整理成三个重点。\n\n"),
            String(localized: "## 当前重点\n\n"),
            String(localized: "产品周会已经确认发布节奏，下一步应先完成路线图并同步会议纪要。\n\n"),
            String(localized: "## 值得保留的线索\n\n"),
            String(localized: "你最近多次记录首页层级和留白，核心方向都是让最重要的信息更早出现。\n\n"),
            String(localized: "## 下一步\n\n"),
            String(localized: "1. 整理路线图\n2. 发送会议纪要\n3. 完成一版无框 Hero 草图")
        ]
        if reduceMotion {
            chunks.append(body.joined())
        } else {
            chunks.append(contentsOf: body)
        }
        return chunks
    }

    private static var completedResponse: String {
        responseChunks(usesWebSearch: false, usesAgent: false, reduceMotion: false).joined()
    }

    static var defaultModelOptions: [NewUIPreviewNottiModel] {
        #if NOTIEE_PLUS
        return [
            NewUIPreviewNottiModel(id: "qwen3.5-plus", title: "Qwen 3.5 Plus"),
            NewUIPreviewNottiModel(id: "deepseek-v4-pro", title: "DeepSeek v4 Pro"),
            NewUIPreviewNottiModel(id: "MiniMax-M3", title: "MiniMax M3")
        ]
        #else
        return CuratedModelCatalog.models(kind: .text).map {
            NewUIPreviewNottiModel(id: $0.id, title: $0.displayName)
        }
        #endif
    }
}
