import Foundation
import OSLog

protocol NottiHistoryPersisting {
    func loadConversations() throws -> [SavedConversation]
    func saveConversations(_ conversations: [SavedConversation]) throws
    func atomicUpdate(_ block: @escaping (inout [SavedConversation]) -> Void) throws
}

final class NottiHistoryStore: NottiHistoryPersisting, @unchecked Sendable {
    private let fileURL: URL
    private let legacyFileURL: URL?
    private static let queue = DispatchQueue(label: "com.notiee.history.serial", qos: .utility)

    static var live: NottiHistoryStore {
        let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return NottiHistoryStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("notti_history.json"),
            legacyFileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("spark_history.json")
        )
    }

    init(fileURL: URL, legacyFileURL: URL? = nil) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL
    }

    func loadConversations() throws -> [SavedConversation] {
        try Self.queue.sync {
            try loadUnsynchronized()
        }
    }

    func saveConversations(_ conversations: [SavedConversation]) throws {
        try Self.queue.sync {
            try saveUnsynchronized(conversations)
        }
    }

    func atomicUpdate(_ block: @escaping (inout [SavedConversation]) -> Void) throws {
        try Self.queue.sync {
            var list = try loadUnsynchronized()
            Logger.logDebug("[history atomicUpdate] load done, count=\(list.count)", category: Logger.notti)
            block(&list)
            try saveUnsynchronized(list)
            Logger.logDebug("[history atomicUpdate] save done, finalCount=\(list.count)", category: Logger.notti)
        }
    }

    private func loadUnsynchronized() throws -> [SavedConversation] {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            if let conversations = try? JSONDecoder().decode([SavedConversation].self, from: data) {
                return conversations
            }
        }
        if let legacyFileURL,
           FileManager.default.fileExists(atPath: legacyFileURL.path) {
            var conversations = try JSONDecoder().decode(
                [SavedConversation].self,
                from: Data(contentsOf: legacyFileURL)
            )
            for index in conversations.indices where conversations[index].title == "Spark" {
                conversations[index].title = "Notti"
            }
            return conversations
        }
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return []
    }

    private func saveUnsynchronized(_ conversations: [SavedConversation]) throws {
        guard !usesLegacyReadOnlyFallback else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sorted = conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
        let data = try JSONEncoder().encode(sorted)
        try data.write(to: fileURL, options: [.atomic])
    }

    private var usesLegacyReadOnlyFallback: Bool {
        guard let legacyFileURL,
              FileManager.default.fileExists(atPath: legacyFileURL.path) else { return false }
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else { return true }
        return (try? JSONDecoder().decode([SavedConversation].self, from: data)) == nil
    }
}
