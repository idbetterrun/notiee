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

        // Try v1 envelope first: { "version": 1, "records": [...] }
        if let envelope = try? JSONDecoder().decode(RecordEnvelope.self, from: data) {
            let records = envelope.records
            if envelope.version < RecordMigrator.currentVersion {
                let migrated = RecordMigrator.migrate(records: records, from: envelope.version)
                try saveRecords(migrated)
                return migrated
            }
            return records
        }

        // Legacy v0: raw [NoteRecord] array
        let records = try JSONDecoder().decode([NoteRecord].self, from: data)
        let migrated = RecordMigrator.migrate(records: records, from: 0)
        try saveRecords(migrated)
        return migrated
    }

    func saveRecords(_ records: [NoteRecord]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let envelope = RecordEnvelope(version: RecordMigrator.currentVersion, records: records)
        let data = try JSONEncoder().encode(envelope)
        try data.write(to: fileURL, options: [.atomic])
    }
}

/// Versioned JSON envelope for records storage.
private struct RecordEnvelope: Codable {
    let version: Int
    let records: [NoteRecord]
}
