import Foundation

enum PersistenceRecovery {
    static func loadOrQuarantine<T>(fileURL: URL, load: () throws -> T) -> T? {
        do {
            return try load()
        } catch {
            quarantine(fileURL: fileURL)
            return nil
        }
    }

    static func quarantine(fileURL: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(stamp)")
        try? fm.moveItem(at: fileURL, to: dest)
    }
}
