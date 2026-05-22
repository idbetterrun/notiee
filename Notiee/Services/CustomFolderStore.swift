import Foundation

protocol CustomFolderPersisting {
    func loadFolders() throws -> [CustomFolder]
    func saveFolders(_ folders: [CustomFolder]) throws
}

struct JSONCustomFolderStore: CustomFolderPersisting {
    let fileURL: URL

    static var live: JSONCustomFolderStore {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return JSONCustomFolderStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("folders.json")
        )
    }

    func loadFolders() throws -> [CustomFolder] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([CustomFolder].self, from: data)
    }

    func saveFolders(_ folders: [CustomFolder]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(folders)
        try data.write(to: fileURL, options: [.atomic])
    }
}
