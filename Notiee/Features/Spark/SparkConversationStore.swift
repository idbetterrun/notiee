import Foundation
import OSLog

// MARK: - Protocol

protocol SparkConversationPersisting {
    func loadDraft() throws -> SparkConversationDraft?
    func saveDraft(_ draft: SparkConversationDraft) throws
    func clearDraft() throws
}

// MARK: - JSON-based Store

final class SparkConversationStore: SparkConversationPersisting {
    private let fileURL: URL

    static var live: SparkConversationStore {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return SparkConversationStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("spark_conversations.json")
        )
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func loadDraft() throws -> SparkConversationDraft? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return nil }

        // Try new draft format first
        if let draft = try? JSONDecoder().decode(SparkConversationDraft.self, from: data) {
            if draft.messages.isEmpty { return nil }
            return draft
        }

        // Fallback: migrate old [ConversationRound] format
        if let oldRounds = try? JSONDecoder().decode([ConversationRound].self, from: data), !oldRounds.isEmpty {
            var messages: [ChatMessage] = []
            for round in oldRounds {
                messages.append(round.userMessage)
                messages.append(round.assistantMessage)
            }
            // Old format has no stored ID; repository will assign one via fingerprint matching
            return SparkConversationDraft(messages: messages, updatedAt: Date())
        }

        return nil
    }

    func saveDraft(_ draft: SparkConversationDraft) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(draft)
        try data.write(to: fileURL, options: [.atomic])
    }

    func clearDraft() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
