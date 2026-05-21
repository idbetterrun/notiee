import Foundation

protocol NoteRecordPersisting {
    func loadRecords() throws -> [NoteRecord]
    func saveRecords(_ records: [NoteRecord]) throws
}

struct JSONNoteRecordStore: NoteRecordPersisting {
    let fileURL: URL

    static var live: JSONNoteRecordStore {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return JSONNoteRecordStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("records.json")
        )
    }

    func loadRecords() throws -> [NoteRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([NoteRecord].self, from: data)
    }

    func saveRecords(_ records: [NoteRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(records)
        try data.write(to: fileURL, options: [.atomic])
    }
}
