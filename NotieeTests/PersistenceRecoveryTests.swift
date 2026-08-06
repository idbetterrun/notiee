import XCTest
@testable import Notiee

final class PersistenceRecoveryTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pr-\(UUID()).json")
    }

    func testLoad_success_returnsValueAndKeepsFile() throws {
        let url = tmpURL()
        try Data("ok".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let value = PersistenceRecovery.loadOrQuarantine(fileURL: url) { "decoded" }

        XCTAssertEqual(value, "decoded")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoad_throws_quarantinesFileAndReturnsNil() throws {
        let url = tmpURL()
        try Data("corrupt".utf8).write(to: url)

        struct Boom: Error {}
        let value: String? = PersistenceRecovery.loadOrQuarantine(fileURL: url) { throw Boom() }

        XCTAssertNil(value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let siblings = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        XCTAssertTrue(siblings.contains { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".corrupt-") })
    }

    func testNottiMigrationCopiesConversationHistorySettingsAndSecretIdempotently() throws {
        let fixture = try makeNottiMigrationFixture()
        defer { fixture.cleanup() }

        let conversationID = UUID()
        let historyID = UUID()
        let message = ChatMessage(role: .user, content: "Spark stays in the message body")
        let legacyDraft = NottiConversationDraft(
            id: conversationID,
            title: "Spark",
            messages: [message],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let legacyHistory = [
            SavedConversation(
                id: historyID,
                title: "Spark",
                createdAt: Date(timeIntervalSince1970: 2_000),
                lastMessageAt: Date(timeIntervalSince1970: 3_000),
                messages: [message]
            ),
            SavedConversation(title: "Spark ideas", messages: [message]),
        ]
        let legacyConversationURL = fixture.directory.appendingPathComponent("spark_conversations.json")
        let legacyHistoryURL = fixture.directory.appendingPathComponent("spark_history.json")
        try JSONEncoder().encode(legacyDraft).write(to: legacyConversationURL, options: .atomic)
        try JSONEncoder().encode(legacyHistory).write(to: legacyHistoryURL, options: .atomic)

        fixture.defaults.set("legacy-style", forKey: UDK.legacySparkCustomStyle)
        fixture.defaults.set("legacy-model", forKey: UDK.legacySparkModelOverride)
        fixture.defaults.set("existing-model", forKey: UDK.nottiModelOverride)
        try fixture.secrets.setString("legacy-secret", forKey: UDK.legacySparkBochaSearchAPIKey)

        try fixture.coordinator.migrateFilesAndSettings()
        let firstConversationData = try Data(
            contentsOf: fixture.directory.appendingPathComponent("notti_conversations.json")
        )
        let firstHistoryData = try Data(
            contentsOf: fixture.directory.appendingPathComponent("notti_history.json")
        )
        try fixture.coordinator.migrateFilesAndSettings()

        let migratedDraft = try JSONDecoder().decode(NottiConversationDraft.self, from: firstConversationData)
        let migratedHistory = try JSONDecoder().decode([SavedConversation].self, from: firstHistoryData)
        XCTAssertEqual(migratedDraft.id, conversationID)
        XCTAssertEqual(migratedDraft.title, "Notti")
        XCTAssertEqual(migratedDraft.messages.map(\.id), [message.id])
        XCTAssertEqual(migratedDraft.messages.first?.content, "Spark stays in the message body")
        XCTAssertEqual(migratedHistory.first?.id, historyID)
        XCTAssertEqual(migratedHistory.first?.title, "Notti")
        XCTAssertEqual(migratedHistory.last?.title, "Spark ideas")
        XCTAssertEqual(fixture.defaults.string(forKey: UDK.nottiCustomStyle), "legacy-style")
        XCTAssertEqual(fixture.defaults.string(forKey: UDK.nottiModelOverride), "existing-model")
        XCTAssertTrue(fixture.defaults.bool(forKey: UDK.nottiAutomaticMemoryEnabled))
        XCTAssertTrue(fixture.defaults.bool(forKey: UDK.nottiMemoryUseEnabled))
        XCTAssertEqual(fixture.secrets.string(forKey: UDK.bochaSearchAPIKey), "legacy-secret")

        fixture.defaults.set("changed-legacy-style", forKey: UDK.legacySparkCustomStyle)
        try fixture.secrets.setString("changed-legacy-secret", forKey: UDK.legacySparkBochaSearchAPIKey)
        try fixture.coordinator.migrateFilesAndSettings()
        XCTAssertEqual(fixture.defaults.string(forKey: UDK.nottiCustomStyle), "legacy-style")
        XCTAssertEqual(fixture.secrets.string(forKey: UDK.bochaSearchAPIKey), "legacy-secret")
        XCTAssertEqual(
            try Data(contentsOf: fixture.directory.appendingPathComponent("notti_conversations.json")),
            firstConversationData
        )
        XCTAssertEqual(
            try Data(contentsOf: fixture.directory.appendingPathComponent("notti_history.json")),
            firstHistoryData
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyConversationURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyHistoryURL.path))
    }

    func testCorruptNottiTargetsRemainUntouchedAndLegacyStoresAreReadOnlyFallbacks() throws {
        let fixture = try makeNottiMigrationFixture()
        defer { fixture.cleanup() }

        let message = ChatMessage(role: .user, content: "Legacy fallback")
        let legacyDraft = NottiConversationDraft(title: "Spark", messages: [message])
        let legacyConversationURL = fixture.directory.appendingPathComponent("spark_conversations.json")
        let currentConversationURL = fixture.directory.appendingPathComponent("notti_conversations.json")
        let legacyHistoryURL = fixture.directory.appendingPathComponent("spark_history.json")
        let currentHistoryURL = fixture.directory.appendingPathComponent("notti_history.json")
        let corruptConversation = Data("corrupt-current-conversation".utf8)
        let corruptHistory = Data("corrupt-current-history".utf8)

        try JSONEncoder().encode(legacyDraft).write(to: legacyConversationURL, options: .atomic)
        try JSONEncoder().encode([
            SavedConversation(title: "Spark", messages: [message])
        ]).write(to: legacyHistoryURL, options: .atomic)
        try corruptConversation.write(to: currentConversationURL, options: .atomic)
        try corruptHistory.write(to: currentHistoryURL, options: .atomic)

        XCTAssertThrowsError(try fixture.coordinator.migrateFilesAndSettings())
        XCTAssertEqual(try Data(contentsOf: currentConversationURL), corruptConversation)
        XCTAssertEqual(try Data(contentsOf: currentHistoryURL), corruptHistory)

        let conversationStore = NottiConversationStore(
            fileURL: currentConversationURL,
            legacyFileURL: legacyConversationURL
        )
        let historyStore = NottiHistoryStore(
            fileURL: currentHistoryURL,
            legacyFileURL: legacyHistoryURL
        )

        let fallbackDraft = try XCTUnwrap(conversationStore.loadDraft())
        XCTAssertEqual(fallbackDraft.title, "Notti")
        XCTAssertEqual(fallbackDraft.messages.map(\.id), [message.id])
        XCTAssertEqual(try historyStore.loadConversations().map(\.title), ["Notti"])
        XCTAssertThrowsError(try conversationStore.saveDraft(fallbackDraft))
        XCTAssertThrowsError(try conversationStore.clearDraft())
        XCTAssertThrowsError(try historyStore.saveConversations([]))
        XCTAssertEqual(try Data(contentsOf: currentConversationURL), corruptConversation)
        XCTAssertEqual(try Data(contentsOf: currentHistoryURL), corruptHistory)
    }

    func testCorruptHistoryPreflightDoesNotCreateConversationDestination() throws {
        let fixture = try makeNottiMigrationFixture()
        defer { fixture.cleanup() }
        let message = ChatMessage(role: .user, content: "Legacy message")
        try JSONEncoder().encode(NottiConversationDraft(title: "Spark", messages: [message])).write(
            to: fixture.directory.appendingPathComponent("spark_conversations.json"),
            options: .atomic
        )
        try JSONEncoder().encode([
            SavedConversation(title: "Spark", messages: [message])
        ]).write(
            to: fixture.directory.appendingPathComponent("spark_history.json"),
            options: .atomic
        )
        let currentHistoryURL = fixture.directory.appendingPathComponent("notti_history.json")
        let corruptData = Data("corrupt".utf8)
        try corruptData.write(to: currentHistoryURL, options: .atomic)

        XCTAssertThrowsError(try fixture.coordinator.migrateFilesAndSettings())

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.directory.appendingPathComponent("notti_conversations.json").path
        ))
        XCTAssertEqual(try Data(contentsOf: currentHistoryURL), corruptData)
    }

    private func makeNottiMigrationFixture() throws -> NottiMigrationFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notti-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "notti-migration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let secrets = NottiMigrationSecretStore()
        return NottiMigrationFixture(
            directory: directory,
            defaults: defaults,
            defaultsSuiteName: suiteName,
            secrets: secrets,
            coordinator: NottiMigrationCoordinator(
                directory: directory,
                defaults: defaults,
                secretStore: secrets
            )
        )
    }
}

private struct NottiMigrationFixture {
    let directory: URL
    let defaults: UserDefaults
    let defaultsSuiteName: String
    let secrets: NottiMigrationSecretStore
    let coordinator: NottiMigrationCoordinator

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }
}

private final class NottiMigrationSecretStore: SecretPersisting {
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        values[key]
    }

    func setString(_ value: String, forKey key: String) throws {
        values[key] = value
    }

    func removeString(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}
