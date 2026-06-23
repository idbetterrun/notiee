import Foundation

/// Handles schema migrations for the records JSON file.
/// Current version: 1.
/// Note: `NoteRecord.source` (added later) is decoded with a safe default
/// (.photo) via NoteRecord.init(from:), so no envelope version bump is required.
enum RecordMigrator {
    static let currentVersion = 1

    static func migrate(records: [NoteRecord], from version: Int) -> [NoteRecord] {
        var result = records
        var current = version

        while current < currentVersion {
            switch current {
            case 0:
                // v0 -> v1: aiRetryCount defaults to 0 via Codable default
                break
            default:
                break
            }
            current += 1
        }

        return result
    }
}
