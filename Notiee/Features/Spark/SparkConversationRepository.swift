import Foundation
import OSLog

// MARK: - Protocol

protocol SparkConversationCoordinating {
    func restoreDraft() throws -> SparkConversationDraft?
    func saveDraft(_ draft: SparkConversationDraft) throws
    func clearDraft() throws
    func upsertHistory(from messages: [ChatMessage], id: UUID, title: String) throws
    func deleteFromHistory(_ ids: Set<UUID>) throws
}

// MARK: - Repository

final class SparkConversationRepository: SparkConversationCoordinating {
    private let draftStore: SparkConversationPersisting
    private let historyStore: SparkHistoryPersisting

    static var live: SparkConversationRepository {
        SparkConversationRepository(
            draftStore: SparkConversationStore.live,
            historyStore: SparkHistoryStore.live
        )
    }

    init(draftStore: SparkConversationPersisting, historyStore: SparkHistoryPersisting) {
        self.draftStore = draftStore
        self.historyStore = historyStore
    }

    // MARK: - Draft

    func restoreDraft() throws -> SparkConversationDraft? {
        guard var draft = try draftStore.loadDraft() else { return nil }

        let history = (try? historyStore.loadConversations()) ?? []

        // Priority 1: if draft already has a non-zero ID and it exists in history, keep it
        if draft.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
           history.contains(where: { $0.id == draft.id }) {
            Logger.spark.debug("[repo] restore draft with existing history ID=\(draft.id)")
            return draft
        }

        // Priority 2: check UserDefaults persisted ID — only use if it exists in history
        if let persistedStr = UserDefaults.standard.string(forKey: UDK.sparkCurrentConversationId),
           let persistedID = UUID(uuidString: persistedStr),
           history.contains(where: { $0.id == persistedID }) {
            draft.id = persistedID
            Logger.spark.debug("[repo] restore draft matched persisted ID=\(persistedID)")
            return draft
        }

        // Priority 3: fingerprint match against history messages
        if let matchedID = findConversationByFingerprint(draft.messages, in: history) {
            draft.id = matchedID
            Logger.spark.debug("[repo] restore draft fingerprint matched ID=\(matchedID)")
            return draft
        }

        // Fresh draft with no match
        Logger.spark.debug("[repo] restore draft fresh, assigned ID=\(draft.id)")
        return draft
    }

    func saveDraft(_ draft: SparkConversationDraft) throws {
        var d = draft
        d.updatedAt = Date()
        try draftStore.saveDraft(d)

        // Persist current conversation ID
        UserDefaults.standard.set(d.id.uuidString, forKey: UDK.sparkCurrentConversationId)
    }

    func clearDraft() throws {
        try draftStore.clearDraft()
        UserDefaults.standard.removeObject(forKey: UDK.sparkCurrentConversationId)
    }

    // MARK: - History

    func upsertHistory(from messages: [ChatMessage], id: UUID, title: String) throws {
        guard !messages.isEmpty else { return }
        try historyStore.atomicUpdate { hist in
            if let idx = hist.firstIndex(where: { $0.id == id }) {
                hist[idx].messages = messages
                hist[idx].lastMessageAt = messages.last?.timestamp ?? Date()
                if !title.isEmpty && title != "Spark" {
                    hist[idx].title = title
                }
                Logger.spark.debug("[repo] upsertHistory updated idx=\(idx) msgCount=\(messages.count)")
            } else {
                let saved = SavedConversation(
                    id: id,
                    title: title,
                    createdAt: messages.first?.timestamp ?? Date(),
                    lastMessageAt: messages.last?.timestamp ?? Date(),
                    messages: messages
                )
                hist.append(saved)
                Logger.spark.debug("[repo] upsertHistory created new id=\(id)")
            }
        }
    }

    func deleteFromHistory(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try historyStore.atomicUpdate { hist in
            hist.removeAll { ids.contains($0.id) }
        }
    }

    // MARK: - Fingerprint matching

    private func findConversationByFingerprint(_ messages: [ChatMessage], in history: [SavedConversation]) -> UUID? {
        guard let firstMsg = messages.first else { return nil }
        for conv in history {
            if let firstHistMsg = conv.messages.first,
               firstHistMsg.content == firstMsg.content,
               firstHistMsg.role == firstMsg.role {
                return conv.id
            }
        }
        return nil
    }
}
