import Foundation

protocol ScheduledEventPersisting {
    func loadEvents() throws -> [ScheduledEvent]
    func saveEvents(_ events: [ScheduledEvent]) throws
}

struct JSONScheduledEventStore: ScheduledEventPersisting {
    let fileURL: URL

    static var live: JSONScheduledEventStore {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return JSONScheduledEventStore(
            fileURL: baseDirectory
                .appendingPathComponent("Notiee", isDirectory: true)
                .appendingPathComponent("custom_events.json")
        )
    }

    func loadEvents() throws -> [ScheduledEvent] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        return try JSONDecoder().decode([ScheduledEvent].self, from: data)
    }

    func saveEvents(_ events: [ScheduledEvent]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(events)
        try data.write(to: fileURL, options: [.atomic])
    }
}
