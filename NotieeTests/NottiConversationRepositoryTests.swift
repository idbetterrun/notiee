import XCTest
@testable import Notiee

// MARK: - Mock Stores

private final class MockDraftStore: NottiConversationPersisting {
    private var draft: NottiConversationDraft?
    var savedDrafts: [NottiConversationDraft] = []
    var clearCount = 0

    func loadDraft() throws -> NottiConversationDraft? { draft }
    func saveDraft(_ draft: NottiConversationDraft) throws {
        savedDrafts.append(draft)
        self.draft = draft
    }
    func clearDraft() throws { draft = nil; clearCount += 1 }
}

private final class MockHistoryStore: NottiHistoryPersisting {
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
final class NottiConversationRepositoryTests: XCTestCase {

    // MARK: - Idempotent upsert

    func testIdempotentUpsertSameID_keepsOneHistoryEntry() throws {
        let hist = MockHistoryStore(initial: [])
        let draft = MockDraftStore()
        let repo = NottiConversationRepository(draftStore: draft, historyStore: hist)

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
        let oldDraft = NottiConversationDraft(messages: [
            ChatMessage(role: .user, content: "What's my dog's name?"),
            ChatMessage(role: .assistant, content: "It's Buddy!"),
        ])
        try draft.saveDraft(oldDraft)
        // Reset savedDrafts to simulate old format (no stored ID)
        draft.savedDrafts = [oldDraft]

        let repo = NottiConversationRepository(draftStore: draft, historyStore: hist)
        let restored = try repo.restoreDraft()

        XCTAssertNotNil(restored, "恢复旧格式草稿应成功")
        XCTAssertEqual(restored?.id, existing.id, "旧格式草稿应通过 fingerprint 匹配到已有历史 ID")
        XCTAssertEqual(restored?.messages.count, 2)
    }

    // MARK: - Persisted ID only if in history

    func testRestoreDraft_persistedIDNotInHistory_fallsBackToFingerprint() throws {
        // Clear UserDefaults first
        UserDefaults.standard.removeObject(forKey: UDK.nottiCurrentConversationId)

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
        UserDefaults.standard.set(stalePersistedID.uuidString, forKey: UDK.nottiCurrentConversationId)

        let draft = MockDraftStore()
        let oldDraft = NottiConversationDraft(messages: [
            ChatMessage(role: .user, content: "Unique question here?"),
            ChatMessage(role: .assistant, content: "Answer."),
        ])
        try draft.saveDraft(oldDraft)

        let repo = NottiConversationRepository(draftStore: draft, historyStore: hist)
        let restored = try repo.restoreDraft()

        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.id, existing.id, "persisted ID 不在历史中时应回退到 fingerprint 匹配")

        UserDefaults.standard.removeObject(forKey: UDK.nottiCurrentConversationId)
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
        let repo = NottiConversationRepository(draftStore: draft, historyStore: hist)

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
        let repo = NottiConversationRepository(draftStore: draft, historyStore: hist)

        try repo.upsertHistory(from: [], id: UUID(), title: "")
        let result = try hist.loadConversations()
        XCTAssertTrue(result.isEmpty, "空消息不应写入历史")
    }

    func testConversationStoreFallsBackToLegacyReadOnlyWithoutChangingBodyOrID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notti-conversation-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let currentURL = directory.appendingPathComponent("notti_conversations.json")
        let legacyURL = directory.appendingPathComponent("spark_conversations.json")
        let corruptData = Data("corrupt".utf8)
        try corruptData.write(to: currentURL, options: .atomic)
        let message = ChatMessage(id: UUID(), role: .user, content: "Spark stays in the message body")
        let draft = NottiConversationDraft(id: UUID(), title: "Spark", messages: [message])
        let legacyData = try JSONEncoder().encode(draft)
        try legacyData.write(to: legacyURL, options: .atomic)
        let store = NottiConversationStore(fileURL: currentURL, legacyFileURL: legacyURL)

        let loaded = try XCTUnwrap(store.loadDraft())
        XCTAssertEqual(loaded.id, draft.id)
        XCTAssertEqual(loaded.title, "Notti")
        XCTAssertEqual(loaded.messages.first?.id, message.id)
        XCTAssertEqual(loaded.messages.first?.content, "Spark stays in the message body")
        XCTAssertThrowsError(try store.saveDraft(loaded))
        XCTAssertEqual(try Data(contentsOf: currentURL), corruptData)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
    }

    func testHistoryStoreFallsBackToLegacyReadOnlyAndOnlyRenamesExactPlaceholder() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notti-history-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let currentURL = directory.appendingPathComponent("notti_history.json")
        let legacyURL = directory.appendingPathComponent("spark_history.json")
        let corruptData = Data("corrupt".utf8)
        try corruptData.write(to: currentURL, options: .atomic)
        let message = ChatMessage(role: .user, content: "Historical Spark body")
        let exact = SavedConversation(id: UUID(), title: "Spark", messages: [message])
        let custom = SavedConversation(id: UUID(), title: "My Spark archive", messages: [message])
        let legacyData = try JSONEncoder().encode([exact, custom])
        try legacyData.write(to: legacyURL, options: .atomic)
        let store = NottiHistoryStore(fileURL: currentURL, legacyFileURL: legacyURL)

        let loaded = try store.loadConversations()
        XCTAssertEqual(loaded.map(\.id), [exact.id, custom.id])
        XCTAssertEqual(loaded.map(\.title), ["Notti", "My Spark archive"])
        XCTAssertEqual(loaded.first?.messages.first?.content, "Historical Spark body")
        XCTAssertThrowsError(try store.saveConversations(loaded))
        XCTAssertEqual(try Data(contentsOf: currentURL), corruptData)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
    }
}
