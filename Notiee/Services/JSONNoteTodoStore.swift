import Foundation

protocol NoteTodoPersisting {
    func loadTodos() throws -> [NoteTodo]
    func saveTodos(_ todos: [NoteTodo]) throws
}

struct JSONNoteTodoStore: NoteTodoPersisting {
    let fileURL: URL

    static var live: JSONNoteTodoStore {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return JSONNoteTodoStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("todos.json")
        )
    }

    func loadTodos() throws -> [NoteTodo] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        // v1 envelope: { "version": 1, "todos": [...] }
        if let envelope = try? JSONDecoder().decode(TodoEnvelope.self, from: data) {
            return envelope.todos
        }

        // Legacy: raw [NoteTodo] array
        return try JSONDecoder().decode([NoteTodo].self, from: data)
    }

    func saveTodos(_ todos: [NoteTodo]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let envelope = TodoEnvelope(version: TodoEnvelope.currentVersion, todos: todos)
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: fileURL, options: [.atomic])
    }
}

/// Versioned JSON envelope for todos storage.
private struct TodoEnvelope: Codable {
    static let currentVersion = 1
    let version: Int
    let todos: [NoteTodo]
}
