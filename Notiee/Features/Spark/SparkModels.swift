import Foundation

// MARK: - Chat Role

enum ChatRole: String, Codable, Sendable {
    case user
    case assistant
}

// MARK: - Citation

struct Citation: Identifiable, Equatable, Codable, Sendable {
    var id: String { recordID.uuidString }
    let recordID: UUID
    let title: String
    let capturedAt: Date
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    let citations: [Citation]

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        citations: [Citation] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.citations = citations
    }
}

// MARK: - Conversation Round

struct ConversationRound: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let userMessage: ChatMessage
    let assistantMessage: ChatMessage
    let createdAt: Date

    init(
        id: UUID = UUID(),
        userMessage: ChatMessage,
        assistantMessage: ChatMessage,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userMessage = userMessage
        self.assistantMessage = assistantMessage
        self.createdAt = createdAt
    }
}

// MARK: - Saved Conversation (for history list)

struct SavedConversation: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var lastMessageAt: Date
    var messages: [ChatMessage]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        lastMessageAt: Date = Date(),
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.lastMessageAt = lastMessageAt
        self.messages = messages
    }

    var messageCount: Int { messages.count }
}

// MARK: - Spark State

enum SparkState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case offline
    case error(String)
}

// MARK: - Random Question Pool

private let questionPool: [String] = [
    "最近一周我拍了哪些内容？",
    "帮我总结最近的会议要点。",
    "我有哪些还没完成的待办？",
    "最近拍的笔记里提到过什么重要日期？",
    "帮我回顾一下上个月的记录。",
    "有哪些关于 SwiftUI 的笔记？",
    "最近拍的图片里写了什么？",
    "整理一下我的学习进度。",
    "有什么值得回顾的灵感？",
    "帮我找找关于项目规划的内容。",
    "今天有什么好心情吗？",
    "回顾一下这周拍的所有板书。",
]

func randomQuestions() -> [String] {
    Array(questionPool.shuffled().prefix(3))
}

// MARK: - Greeting Phrase

struct GreetingPhrase: Sendable {
    let emoji: String
    private let rawText: String

    var text: String { NSLocalizedString(rawText, comment: "") }

    init(emoji: String, text: String) {
        self.emoji = emoji
        self.rawText = text
    }

    static let pool: [GreetingPhrase] = [
        GreetingPhrase(emoji: "\u{1F44B}", text: "嗨，又见面了"),
        GreetingPhrase(emoji: "\u{2728}", text: "有什么想聊的？"),
        GreetingPhrase(emoji: "\u{2600}\u{FE0F}", text: "今天是个适合整理知识的好日子"),
        GreetingPhrase(emoji: "\u{1F4A1}", text: "有什么灵感需要记录的吗"),
        GreetingPhrase(emoji: "\u{1F4D6}", text: "翻翻最近的拍记吧"),
        GreetingPhrase(emoji: "\u{1F3AF}", text: "今天过得怎么样？"),
        GreetingPhrase(emoji: "\u{1FAF0}", text: "随时准备好帮你回顾笔记"),
        GreetingPhrase(emoji: "\u{1F52E}", text: "我帮你理一理思路"),
    ]

    static func random() -> GreetingPhrase { pool.randomElement()! }
}
