import Foundation
import OSLog

protocol SparkHistoryPersisting {
    func loadConversations() throws -> [SavedConversation]
    func saveConversations(_ conversations: [SavedConversation]) throws
    func atomicUpdate(_ block: @escaping (inout [SavedConversation]) -> Void) throws
}

final class SparkHistoryStore: SparkHistoryPersisting, @unchecked Sendable {
    private let fileURL: URL
    private static let queue = DispatchQueue(label: "com.notiee.history.serial", qos: .utility)

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
            Logger.logDebug("[history atomicUpdate] load done, count=\(list.count)", category: Logger.spark)
            block(&list)
            try saveUnsynchronized(list)
            Logger.logDebug("[history atomicUpdate] save done, finalCount=\(list.count)", category: Logger.spark)
        }
    }

    private func loadUnsynchronized() throws -> [SavedConversation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([SavedConversation].self, from: data)
    }

    private func saveUnsynchronized(_ conversations: [SavedConversation]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let sorted = conversations.sorted { $0.lastMessageAt > $1.lastMessageAt }
        let data = try JSONEncoder().encode(sorted)
        try data.write(to: fileURL, options: [.atomic])
    }
}
