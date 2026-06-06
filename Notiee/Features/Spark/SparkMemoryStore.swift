import Foundation

// MARK: - Protocol

protocol SparkMemoryPersisting {
    func load() throws -> [String: String]
    func save(_ dict: [String: String]) throws
    func set(_ key: String, value: String)
    func get(_ key: String) -> String?
    func delete(_ key: String)
}

// MARK: - JSON Store

final class SparkMemoryStore: SparkMemoryPersisting, @unchecked Sendable {
    private let fileURL: URL
    private static let queue = DispatchQueue(label: "com.notiee.memory.serial", qos: .utility)

    static var live: SparkMemoryStore {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return SparkMemoryStore(fileURL: base
            .appendingPathComponent("Notiee", isDirectory: true)
            .appendingPathComponent("spark_memory.json"))
    }

    init(fileURL: URL) { self.fileURL = fileURL }

    func load() throws -> [String: String] {
        try Self.queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
            let data = try Data(contentsOf: fileURL)
            guard !data.isEmpty else { return [:] }
            return try JSONDecoder().decode([String: String].self, from: data)
        }
    }

    func save(_ dict: [String: String]) throws {
        try Self.queue.sync {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(dict).write(to: fileURL, options: .atomic)
        }
    }

    func set(_ key: String, value: String) {
        Self.queue.async { [fileURL] in
            var dict = (try? Self.loadFrom(fileURL)) ?? [:]
            dict[key] = value
            try? Self.saveTo(dict, fileURL: fileURL)
        }
    }

    func get(_ key: String) -> String? {
        Self.queue.sync {
            (try? Self.loadFrom(fileURL))?[key]
        }
    }

    func delete(_ key: String) {
        Self.queue.async { [fileURL] in
            var dict = (try? Self.loadFrom(fileURL)) ?? [:]
            dict.removeValue(forKey: key)
            try? Self.saveTo(dict, fileURL: fileURL)
        }
    }

    private static func loadFrom(_ url: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private static func saveTo(_ dict: [String: String], fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(dict).write(to: fileURL, options: .atomic)
    }
}
