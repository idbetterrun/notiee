import XCTest
@testable import Notiee

// MARK: - Mock Stores

private final class MockDraftStore: SparkConversationPersisting {
    private var draft: SparkConversationDraft?
    var savedDrafts: [SparkConversationDraft] = []
    var clearCount = 0

    func loadDraft() throws -> SparkConversationDraft? { draft }
    func saveDraft(_ draft: SparkConversationDraft) throws {
        savedDrafts.append(draft)
        self.draft = draft
    }
    func clearDraft() throws { draft = nil; clearCount += 1 }
}

private final class MockHistoryStore: SparkHistoryPersisting {
    private var conversations: [SavedConversation] = []
    private let queue = DispatchQueue(label: "com.notiee.test.histmock")

    init(initial: [SavedConversation]) { self.conversations = initial }

    func loadConversations() throws -> [SavedConversation] {
        queue.sync { conversations }
    }
    func saveConversations(_ conversations: [SavedConversation]) throws {
        queue.sync { self.conversations = conversations }
    }
    func atomicUpdate(_ block: @escaping (inout [SavedConversation]) -> Void) throws {
        try queue.sync {
            block(&conversations)
        }
    }
}

// MARK: - Tests

@MainActor
final class SparkConversationRepositoryTests: XCTestCase {

    // MARK: - Idempotent upsert

    func testIdempotentUpsertSameID_keepsOneHistoryEntry() throws {
        let hist = MockHistoryStore(initial: [])
        let draft = MockDraftStore()
        let repo = SparkConversationRepository(draftStore: draft, historyStore: hist)

        let msgs = [
            ChatMessage(role: .user, content: "Hello"),
            ChatMessage(role: .assistant, content: "Hi there"),
        ]
        let convID = UUID()

        try repo.upsertHistory(from: msgs, id: convID, title: "Test")
        try repo.upsertHistory(from: msgs, id: convID, title: "Test")
        try repo.upsertHistory(from: msgs, id: convID, title: "Test")

        let result = try hist.loadConversations()
        XCTAssertEqual(result.count, 1, "同一个 conversation ID 连续 upsert 多次，历史只应保留 1 条")
        XCTAssertEqual(result.first?.id, convID)
    }

    // MARK: - Fingerprint matching

    func testOldFormatDraft_fingerprintMatchesHistoryID() throws {
        let existing = SavedConversation(
            id: UUID(),
            title: "Old",
            messages: [
                ChatMessage(role: .user, content: "What's my dog's name?"),
                ChatMessage(role: .assistant, content: "It's Buddy!"),
            ]
        )
        let hist = MockHistoryStore(initial: [existing])
        let draft = MockDraftStore()

        // Pre-populate draft store with old-format content (same first message)
        draft.savedDrafts = []
        let oldDraft = SparkConversationDraft(messages: [
            ChatMessage(role: .user, content: "What's my dog's name?"),
            ChatMessage(role: .assistant, content: "It's Buddy!"),
        ])
        try draft.saveDraft(oldDraft)
        // Reset savedDrafts to simulate old format (no stored ID)
        draft.savedDrafts = [oldDraft]

        let repo = SparkConversationRepository(draftStore: draft, historyStore: hist)
        let restored = try repo.restoreDraft()

        XCTAssertNotNil(restored, "恢复旧格式草稿应成功")
        XCTAssertEqual(restored?.id, existing.id, "旧格式草稿应通过 fingerprint 匹配到已有历史 ID")
        XCTAssertEqual(restored?.messages.count, 2)
    }

    // MARK: - Persisted ID only if in history

    func testRestoreDraft_persistedIDNotInHistory_fallsBackToFingerprint() throws {
        // Clear UserDefaults first
        UserDefaults.standard.removeObject(forKey: UDK.sparkCurrentConversationId)

        let existing = SavedConversation(
            id: UUID(),
            title: "History Item",
            messages: [
                ChatMessage(role: .user, content: "Unique question here?"),
                ChatMessage(role: .assistant, content: "Answer."),
            ]
        )
        let hist = MockHistoryStore(initial: [existing])

        let stalePersistedID = UUID() // Not in history
        UserDefaults.standard.set(stalePersistedID.uuidString, forKey: UDK.sparkCurrentConversationId)

        let draft = MockDraftStore()
        let oldDraft = SparkConversationDraft(messages: [
            ChatMessage(role: .user, content: "Unique question here?"),
            ChatMessage(role: .assistant, content: "Answer."),
        ])
        try draft.saveDraft(oldDraft)

        let repo = SparkConversationRepository(draftStore: draft, historyStore: hist)
        let restored = try repo.restoreDraft()

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.id, existing.id, "persisted ID 不在历史中时应回退到 fingerprint 匹配")

        UserDefaults.standard.removeObject(forKey: UDK.sparkCurrentConversationId)
    }

    // MARK: - Loaded conversation update

    func testLoadedConversationSecondRound_updatesOriginalEntry() throws {
        let convID = UUID()
        let original = SavedConversation(
            id: convID,
            title: "Original",
            createdAt: Date(),
            lastMessageAt: Date(),
            messages: [
                ChatMessage(role: .user, content: "Q1"),
                ChatMessage(role: .assistant, content: "A1"),
            ]
        )
        let hist = MockHistoryStore(initial: [original])
        let draft = MockDraftStore()
        let repo = SparkConversationRepository(draftStore: draft, historyStore: hist)

        let updatedMsgs = original.messages + [
            ChatMessage(role: .user, content: "Q2"),
            ChatMessage(role: .assistant, content: "A2"),
        ]
        try repo.upsertHistory(from: updatedMsgs, id: convID, title: "Original")

        let result = try hist.loadConversations()
        XCTAssertEqual(result.count, 1, "从历史加载的对话继续聊天后仍应只有 1 条历史")
        XCTAssertEqual(result.first?.messages.count, 4, "应更新为 4 条消息")
        XCTAssertEqual(result.first?.id, convID)
    }

    // MARK: - Empty conversations

    func testUpsertHistory_emptyMessages_noOp() throws {
        let hist = MockHistoryStore(initial: [])
        let draft = MockDraftStore()
        let repo = SparkConversationRepository(draftStore: draft, historyStore: hist)

        try repo.upsertHistory(from: [], id: UUID(), title: "")
        let result = try hist.loadConversations()
        XCTAssertTrue(result.isEmpty, "空消息不应写入历史")
    }
}
