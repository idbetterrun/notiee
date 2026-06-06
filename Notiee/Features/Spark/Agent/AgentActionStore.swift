import Foundation

enum AgentActionStoreError: Error {
    case notUndoable
    case undoExpired
    case toolNotFound
}

final class AgentActionStore {
    private let fileURL: URL
    private let snapshotsDir: URL
    private let queue = DispatchQueue(label: "com.notiee.agent.action.store")

    init(fileURL: URL? = nil, snapshotsDir: URL? = nil) {
        let base = fileURL?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Notiee", isDirectory: true)
        self.fileURL = fileURL ?? base.appendingPathComponent("AgentActions.json")
        self.snapshotsDir = snapshotsDir ?? base.appendingPathComponent("AgentSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
    }

    func save(_ action: AgentAction) {
        queue.async {
            var actions = self.loadAll()
            actions.append(action)
            self.writeAll(actions)
        }
    }

    func get(_ id: UUID) -> AgentAction? {
        queue.sync {
            loadAll().first { $0.id == id }
        }
    }

    func recent(_ limit: Int = 50) -> [AgentAction] {
        queue.sync {
            Array(loadAll().suffix(limit).reversed())
        }
    }

    func writeSnapshot(id: UUID, data: Data) throws -> String {
        let path = snapshotsDir.appendingPathComponent("\(id.uuidString).json")
        try data.write(to: path, options: .atomic)
        let fd = open(path.path, O_WRONLY)
        if fd != -1 { fcntl(fd, F_FULLFSYNC); close(fd) }
        return path.path
    }

    func readSnapshot(path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func deleteSnapshot(path: String) throws {
        try FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    func purgeExpiredSnapshots(ttlMinutes: Int) {
        queue.async {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: self.snapshotsDir, includingPropertiesForKeys: [.creationDateKey]) else { return }
            let cutoff = Date().addingTimeInterval(-Double(ttlMinutes) * 60)
            for url in contents {
                guard let attrs = try? url.resourceValues(forKeys: [.creationDateKey]),
                      let created = attrs.creationDate, created < cutoff else { continue }
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func recoverOrphanSnapshots() async {
        // Placeholder: App will scan AgentSnapshots/ on launch
        // and recover any snapshots without matching action records
    }

    private func loadAll() -> [AgentAction] {
        guard let data = try? Data(contentsOf: fileURL),
              let actions = try? JSONDecoder().decode([AgentAction].self, from: data) else { return [] }
        return actions
    }

    private func writeAll(_ actions: [AgentAction]) {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
