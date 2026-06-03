import Foundation

// MARK: - Protocol

protocol SparkConversationPersisting {
    func loadConversations() throws -> [ConversationRound]
    func saveConversations(_ conversations: [ConversationRound]) throws
}

// MARK: - JSON-based Store

final class SparkConversationStore: SparkConversationPersisting {
    private let fileURL: URL
    private let maxRounds: Int

    static var live: SparkConversationStore {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return SparkConversationStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("spark_conversations.json"),
            maxRounds: 20
        )
    }

    init(fileURL: URL, maxRounds: Int = 20) {
        self.fileURL = fileURL
        self.maxRounds = maxRounds
    }

    func loadConversations() throws -> [ConversationRound] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([ConversationRound].self, from: data)
    }

    func saveConversations(_ conversations: [ConversationRound]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Keep only the most recent rounds
        let trimmed = Array(conversations.suffix(maxRounds))
        let data = try JSONEncoder().encode(trimmed)
        try data.write(to: fileURL, options: [.atomic])
    }
}
