import Foundation
import OSLog

// MARK: - Protocol

protocol NottiConversationPersisting {
    func loadDraft() throws -> NottiConversationDraft?
    func saveDraft(_ draft: NottiConversationDraft) throws
    func clearDraft() throws
}

// MARK: - JSON-based Store

final class NottiConversationStore: NottiConversationPersisting {
    private let fileURL: URL
    private let legacyFileURL: URL?

    static var live: NottiConversationStore {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return NottiConversationStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("notti_conversations.json"),
            legacyFileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("spark_conversations.json")
        )
    }

    init(fileURL: URL, legacyFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL
    }

    func loadDraft() throws -> NottiConversationDraft? {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            if let draft = Self.decodeDraft(data, renameLegacyPlaceholder: false) {
                return draft
            }
        }
        if let legacyFileURL,
           FileManager.default.fileExists(atPath: legacyFileURL.path) {
            return Self.decodeDraft(
                try Data(contentsOf: legacyFileURL),
                renameLegacyPlaceholder: true
            )
        }
        return nil
    }

    private static func decodeDraft(
        _ data: Data,
        renameLegacyPlaceholder: Bool
    ) -> NottiConversationDraft? {
        guard !data.isEmpty else { return nil }
        if var draft = try? JSONDecoder().decode(NottiConversationDraft.self, from: data),
           !draft.messages.isEmpty {
            if renameLegacyPlaceholder, draft.title == "Spark" { draft.title = "Notti" }
            return draft
        }
        if let oldRounds = try? JSONDecoder().decode([ConversationRound].self, from: data), !oldRounds.isEmpty {
            var messages: [ChatMessage] = []
            for round in oldRounds {
                messages.append(round.userMessage)
                messages.append(round.assistantMessage)
            }
            return NottiConversationDraft(messages: messages, updatedAt: Date())
        }
        return nil
    }

    func saveDraft(_ draft: NottiConversationDraft) throws {
        guard !usesLegacyReadOnlyFallback else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(draft)
        try data.write(to: fileURL, options: [.atomic])
    }

    func clearDraft() throws {
        guard !usesLegacyReadOnlyFallback else { throw CocoaError(.fileWriteNoPermission) }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private var usesLegacyReadOnlyFallback: Bool {
        guard let legacyFileURL,
              FileManager.default.fileExists(atPath: legacyFileURL.path) else { return false }
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return true }
        return Self.decodeDraft(data, renameLegacyPlaceholder: false) == nil
    }
}
