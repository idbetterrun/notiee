import Foundation

/// Handles schema migrations for the records JSON file.
/// Current version: 1 (introduced with aiRetryCount field).
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
