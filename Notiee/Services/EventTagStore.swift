import Foundation

protocol EventTagPersisting {
    func loadTags() throws -> [EventTag]
    func saveTags(_ tags: [EventTag]) throws
}

struct JSONEventTagStore: EventTagPersisting {
    let fileURL: URL

    static var live: JSONEventTagStore {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return JSONEventTagStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("tags.json")
        )
    }

    func loadTags() throws -> [EventTag] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([EventTag].self, from: data)
    }

    func saveTags(_ tags: [EventTag]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(tags)
        try data.write(to: fileURL, options: [.atomic])
    }
}
