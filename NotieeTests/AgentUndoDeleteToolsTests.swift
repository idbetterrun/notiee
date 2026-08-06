import XCTest
@testable import Notiee

@MainActor
final class AgentUndoDeleteToolsTests: XCTestCase {
    private func makeManager(_ records: [NoteRecord], _ todos: [NoteTodo]) -> RecordManager {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID()).json")
        return RecordManager(
            records: records, todos: todos,
            recordStore: JSONNoteRecordStore(fileURL: url),
            todoStore: JSONNoteTodoStore(fileURL: url.appendingPathExtension("todos")))
    }

    func testNoteDeleteTool_removesRecord() async throws {
        let rec = NoteRecord(localImagePaths: [], title: "t", processingState: .completed)
        let mgr = makeManager([rec], [])
        let tool = NoteDeleteTool(recordManager: mgr)

        let result = try await tool.execute(parameters: ["record_id": rec.id.uuidString])

        XCTAssertTrue(result.success)
        XCTAssertFalse(mgr.records.contains { $0.id == rec.id })
    }

    func testTodoDeleteTool_removesTodo() async throws {
        let todo = NoteTodo(recordID: nil, content: "x")
        let mgr = makeManager([], [todo])
        let tool = TodoDeleteTool(recordManager: mgr)

        let result = try await tool.execute(parameters: ["todo_id": todo.id.uuidString])

        XCTAssertTrue(result.success)
        XCTAssertFalse(mgr.todos.contains { $0.id == todo.id })
    }

    func testDeleteTools_areHiddenFromModel() {
        let rec = makeManager([], [])
        let registry = AgentToolRegistry(tools: [
            NoteDeleteTool(recordManager: rec),
            TodoDeleteTool(recordManager: rec)
        ])
        XCTAssertNotNil(registry.get("note_delete"))
        let modelNames = registry.allTools(for: .full).map { $0.name }
        XCTAssertFalse(modelNames.contains("note_delete"))
        XCTAssertFalse(modelNames.contains("todo_delete"))
    }

    func testMemoryForgetIsNotExecutedWithoutPerActionConfirmation() async throws {
        let repository = try makeMemoryRepository()
        let memoryID = try await addMemory(to: repository)
        let tool = MemoryForgetTool(repository: repository)
        let executor = makeExecutor(
            tool: tool,
            memoryID: memoryID,
            confirmsDestructiveAction: false
        )
        var completedAction: AgentAction?

        _ = try await executor.run(
            userMessage: "Forget this memory",
            conversationHistory: [],
            onToolCallStart: { _ in },
            onToolCallEnd: { completedAction = $0 }
        )

        let retainedMemory = try await repository.memory(id: memoryID)
        XCTAssertEqual(tool.permission, .destructive)
        XCTAssertNotNil(retainedMemory)
        XCTAssertEqual(completedAction?.toolName, "memory_forget")
        XCTAssertEqual(completedAction?.result.success, false)
        XCTAssertEqual(completedAction?.result.shouldTerminate, true)
        XCTAssertTrue(completedAction?.result.message.contains("未确认") == true)
    }

    func testMemoryForgetExecutesOnlyAfterPerActionConfirmation() async throws {
        let repository = try makeMemoryRepository()
        let expectedID = try await addMemory(to: repository)
        let tool = MemoryForgetTool(repository: repository)
        var confirmationName: String?
        var confirmationMemoryID: String?
        let executor = makeExecutor(
            tool: tool,
            memoryID: expectedID,
            confirmsDestructiveAction: true,
            onConfirmation: { name, parameters in
                confirmationName = name
                confirmationMemoryID = parameters["memory_id"] as? String
            }
        )

        _ = try await executor.run(
            userMessage: "Forget this memory",
            conversationHistory: [],
            onToolCallStart: { _ in },
            onToolCallEnd: { _ in }
        )

        let deletedMemory = try await repository.memory(id: expectedID)
        XCTAssertEqual(confirmationName, "memory_forget")
        XCTAssertEqual(confirmationMemoryID, expectedID.uuidString)
        XCTAssertNil(deletedMemory)
    }

    private func makeExecutor(
        tool: any AgentTool,
        memoryID: UUID = UUID(),
        confirmsDestructiveAction: Bool,
        onConfirmation: @escaping (String, [String: Any]) -> Void = { _, _ in }
    ) -> AgentExecutor {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-confirmation-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "agent-confirmation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let settings = UserDefaultsAppSettingsStore(
            userDefaults: defaults,
            secretStore: AgentConfirmationSecretStore()
        )
        let trustManager = AgentTrustManager(settingsStore: settings)
        trustManager.setLevel(.full)

        return AgentExecutor(
            aiService: MemoryForgetAIService(memoryID: memoryID),
            toolRegistry: AgentToolRegistry(tools: [tool]),
            actionStore: AgentActionStore(
                fileURL: root.appendingPathComponent("actions.json"),
                snapshotsDir: root.appendingPathComponent("snapshots", isDirectory: true)
            ),
            trustManager: trustManager,
            confirmDestructiveAction: { name, parameters in
                onConfirmation(name, parameters)
                return confirmsDestructiveAction
            }
        )
    }

    private func makeMemoryRepository() throws -> NottiMemoryRepository {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-memory-forget-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return NottiMemoryRepository(
            snapshotURL: root.appendingPathComponent("memory.enc"),
            vectorURL: root.appendingPathComponent("vectors.enc"),
            secretStore: AgentConfirmationSecretStore()
        )
    }

    private func addMemory(to repository: NottiMemoryRepository) async throws -> UUID {
        let text = "I prefer jasmine tea"
        let resolutions = try await repository.applyProposals(
            [NottiMemoryProposal(
                text: text,
                category: .preference,
                durability: .stable,
                topicKey: "preference.tea",
                evidenceQuote: text
            )],
            sourceMessageID: UUID(),
            sourceText: text
        )
        guard case let .added(memoryID) = try XCTUnwrap(resolutions.first) else {
            throw NottiMemoryRepositoryError.invalidEvidence
        }
        return memoryID
    }
}

private final class MemoryForgetAIService: NottiAIServing, @unchecked Sendable {
    private let memoryID: UUID

    init(memoryID: UUID) {
        self.memoryID = memoryID
    }

    func ask(
        question: String,
        recall: RecalledRecords,
        recentRounds: [ConversationRound],
        upcomingEvents: [ScheduledEvent],
        pinnedRecordIDs: [UUID]
    ) async throws -> (text: String, tokens: Int) {
        ("", 0)
    }

    func accumulatePublic(_ tokens: Int) {}
    func extractCitations(from text: String, recordCount: Int) -> [Int] { [] }
    func extractCitationsFallback(from text: String, records: [NoteRecord]) -> [Int] { [] }
    func generateTitle(for message: String) async throws -> String { "" }
    func generateContextualTitle(from rounds: [ConversationRound]) async throws -> String { "" }

    func agentChat(messages: [[String: Any]], tools: [[String: Any]]) async throws -> AgentChatResponse {
        AgentChatResponse(
            text: "",
            toolCalls: [
                AgentToolCall(
                    id: "memory-forget-call",
                    name: "memory_forget",
                    parameters: ["memory_id": memoryID.uuidString]
                )
            ],
            tokensUsed: 0
        )
    }
}

private final class AgentConfirmationSecretStore: SecretPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func setString(_ value: String, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func removeString(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }
}
