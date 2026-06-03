import Foundation

protocol SparkHistoryPersisting {
    func loadConversations() throws -> [SavedConversation]
    func saveConversations(_ conversations: [SavedConversation]) throws
}

final class SparkHistoryStore: SparkHistoryPersisting {
    private let fileURL: URL

    static var live: SparkHistoryStore {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return SparkHistoryStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("spark_history.json")
        )
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func loadConversations() throws -> [SavedConversation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([SavedConversation].self, from: data)
    }

    func saveConversations(_ conversations: [SavedConversation]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sorted = conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
        let data = try JSONEncoder().encode(sorted)
        try data.write(to: fileURL, options: [.atomic])
    }
}
