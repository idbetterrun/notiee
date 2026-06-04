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

final class SparkMemoryStore: SparkMemoryPersisting {
    private let fileURL: URL

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
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    func save(_ dict: [String: String]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(dict).write(to: fileURL, options: .atomic)
    }

    func set(_ key: String, value: String) {
        var dict = (try? load()) ?? [:]
        dict[key] = value
        try? save(dict)
    }

    func get(_ key: String) -> String? {
        (try? load())?[key]
    }

    func delete(_ key: String) {
        var dict = (try? load()) ?? [:]
        dict.removeValue(forKey: key)
        try? save(dict)
    }
}
