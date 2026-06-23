import Foundation

struct EmbeddingEntry: Codable, Equatable, Sendable {
    let vector: [Float]
    let model: String
    let contentHash: String
}

/// 拍记向量的旁路存储。与 NoteRecord JSON 解耦，可独立重算/失效。
@MainActor
final class EmbeddingIndex {
    private let fileURL: URL
    private var entries: [UUID: EmbeddingEntry]

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([UUID: EmbeddingEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = [:]
        }
    }

    func entry(for id: UUID) -> EmbeddingEntry? { entries[id] }

    func set(_ entry: EmbeddingEntry, for id: UUID) {
        entries[id] = entry
        save()
    }

    func remove(id: UUID) {
        entries[id] = nil
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 默认位置：Application Support/embedding-index.json
    static let live: EmbeddingIndex = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return EmbeddingIndex(fileURL: dir.appendingPathComponent("embedding-index.json"))
    }()
}
