import CryptoKit
import XCTest
@testable import Notiee

final class NottiTierLimitsTests: XCTestCase {

    // 测试跑在 Notiee(免费) target，CurrentEntitlement.tier == .free

    func testFreeTierSessionRoundCapIs20() {
        XCTAssertEqual(NottiTierLimits.maxSessionRounds, 20)
    }

    func testFreeTierRecallCapIs5() {
        XCTAssertEqual(NottiTierLimits.maxMemoryRecallCount, 5)
    }

    func testFreeTierAgentNotAllowed() {
        XCTAssertFalse(NottiTierLimits.isAgentAllowed)
    }

    func testFreeTierAllowsOnlyFlashText() {
        XCTAssertTrue(NottiTierLimits.isTextModelAllowed("deepseek-v4-flash"))
        XCTAssertFalse(NottiTierLimits.isTextModelAllowed("MiniMax-M3"))
        XCTAssertFalse(NottiTierLimits.isTextModelAllowed("does-not-exist"))
    }

    func testSessionRoundLimitBoundary() {
        XCTAssertFalse(NottiTierLimits.sessionRoundLimitReached(currentRounds: 19))
        XCTAssertTrue(NottiTierLimits.sessionRoundLimitReached(currentRounds: 20))
        XCTAssertTrue(NottiTierLimits.sessionRoundLimitReached(currentRounds: 21))
    }

    func testAcceptedNewMemoryCountDoesNotLimitStorage() {
        XCTAssertEqual(NottiTierLimits.acceptedNewMemoryCount(existingCount: 5, incoming: 3), 3)
        XCTAssertEqual(NottiTierLimits.acceptedNewMemoryCount(existingCount: 3, incoming: 3), 3)
        XCTAssertEqual(NottiTierLimits.acceptedNewMemoryCount(existingCount: 0, incoming: 4), 4)
    }
}

final class BackendNottiMemoryExtractorContractTests: XCTestCase {
    func testRequestBodyAppliesFreeBackendBoundsAndSelectedModel() throws {
        let job = NottiMemoryExtractionJob(
            userMessageID: UUID(),
            userMessage: String(repeating: "用", count: 4_100),
            confirmedToolResults: (0..<10).map { index in
                "tool-\(index): " + String(repeating: "结", count: 2_100)
            }
        )
        let candidates = (0..<10).map { index in
            NottiMemoryExtractionCandidate(
                id: UUID(),
                text: String(repeating: "候", count: 510),
                category: .preference,
                topicKey: String(repeating: "题", count: 130) + "-\(index)"
            )
        }

        let body = BackendNottiMemoryExtractor.makeRequestBody(
            job: job,
            candidates: candidates,
            model: "deepseek-v4-flash"
        )

        XCTAssertEqual(body["model"] as? String, "deepseek-v4-flash")
        XCTAssertEqual((body["userMessage"] as? String)?.count, 4_000)
        let toolResults = try XCTUnwrap(body["confirmedToolResults"] as? [String])
        XCTAssertEqual(toolResults.count, 8)
        XCTAssertTrue(toolResults.allSatisfy { $0.count == 2_000 })
        let encodedCandidates = try XCTUnwrap(body["candidates"] as? [[String: Any]])
        XCTAssertEqual(encodedCandidates.count, 8)
        XCTAssertTrue(encodedCandidates.allSatisfy { ($0["text"] as? String)?.count == 500 })
        XCTAssertTrue(encodedCandidates.allSatisfy { ($0["topicKey"] as? String)?.count == 120 })
    }

    func testResponseDecoderAcceptsContractAndRejectsMalformedTemporalFields() throws {
        let valid: [String: Any] = [
            "proposals": [[
                "text": "我喜欢拿铁",
                "category": "preference",
                "durability": "stable",
                "topicKey": "preference.coffee",
                "entities": ["拿铁"],
                "keywords": ["咖啡"],
                "eventAt": NSNull(),
                "expiresAt": "2026-12-01T00:00:00Z",
                "evidenceQuote": "我喜欢拿铁",
                "evidenceSource": "user",
                "relatedMemoryID": NSNull(),
                "relationship": "none",
            ]],
        ]

        let proposals = try BackendNottiMemoryExtractor.decodeResponse(valid)
        XCTAssertEqual(proposals.count, 1)
        XCTAssertNotNil(proposals[0].expiresAt)

        var invalid = valid
        var proposal = try XCTUnwrap((valid["proposals"] as? [[String: Any]])?.first)
        proposal["expiresAt"] = "not-a-date"
        invalid["proposals"] = [proposal]
        XCTAssertThrowsError(try BackendNottiMemoryExtractor.decodeResponse(invalid))
    }

    func testSharedProposalDecoderRejectsInvalidIDsLegacyEvidenceAndOversizedFields() throws {
        let validProposal: [String: Any] = [
            "text": "我喜欢拿铁",
            "category": "preference",
            "durability": "stable",
            "topicKey": "preference.coffee",
            "entities": ["拿铁"],
            "keywords": ["咖啡"],
            "eventAt": NSNull(),
            "expiresAt": NSNull(),
            "evidenceQuote": "我喜欢拿铁",
            "evidenceSource": "user",
            "relatedMemoryID": NSNull(),
            "relationship": "none",
        ]

        func encoded(_ proposal: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["proposals": [proposal]])
        }

        var invalidUUID = validProposal
        invalidUUID["relatedMemoryID"] = "not-a-uuid"
        invalidUUID["relationship"] = "merge"
        XCTAssertThrowsError(try NottiMemoryProposalDecoder.decode(encoded(invalidUUID)))

        var inconsistentRelationship = validProposal
        inconsistentRelationship["relatedMemoryID"] = UUID().uuidString
        XCTAssertThrowsError(try NottiMemoryProposalDecoder.decode(encoded(inconsistentRelationship)))

        var legacyEvidence = validProposal
        legacyEvidence["evidenceSource"] = "legacy"
        XCTAssertThrowsError(try NottiMemoryProposalDecoder.decode(encoded(legacyEvidence)))

        var oversized = validProposal
        oversized["text"] = String(repeating: "x", count: 501)
        oversized["entities"] = Array(repeating: "entity", count: 21)
        XCTAssertThrowsError(try NottiMemoryProposalDecoder.decode(encoded(oversized)))
    }

    func testSharedProposalDecoderRequiresExactEnvelopeAndProposalSchema() throws {
        let validProposal: [String: Any] = [
            "text": "我喜欢拿铁",
            "category": "preference",
            "durability": "stable",
            "topicKey": "preference.coffee",
            "entities": ["拿铁"],
            "keywords": ["咖啡"],
            "eventAt": NSNull(),
            "expiresAt": NSNull(),
            "evidenceQuote": "我喜欢拿铁",
            "evidenceSource": "user",
            "relatedMemoryID": NSNull(),
            "relationship": "none",
        ]

        func encoded(_ root: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: root)
        }

        XCTAssertNoThrow(try NottiMemoryProposalDecoder.decode(encoded(["proposals": [validProposal]])))
        XCTAssertThrowsError(try NottiMemoryProposalDecoder.decode(encoded([
            "proposals": [validProposal],
            "unexpected": true,
        ])))

        var unknownProposalField = validProposal
        unknownProposalField["unexpected"] = true
        XCTAssertThrowsError(try NottiMemoryProposalDecoder.decode(encoded([
            "proposals": [unknownProposalField],
        ])))

        for requiredNullableField in ["eventAt", "expiresAt", "relatedMemoryID"] {
            var missingField = validProposal
            missingField.removeValue(forKey: requiredNullableField)
            XCTAssertThrowsError(
                try NottiMemoryProposalDecoder.decode(encoded(["proposals": [missingField]])),
                "Missing explicit nullable field must be rejected: \(requiredNullableField)"
            )
        }
    }
}

final class NottiMemoryRepositoryTests: XCTestCase {
    private final class MemorySecretStore: SecretPersisting, @unchecked Sendable {
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
            values[key] = nil
        }
    }

    private final class ThrowingSecretStore: SecretPersisting, @unchecked Sendable {
        func string(forKey key: String) -> String? { nil }
        func setString(_ value: String, forKey key: String) throws {
            throw CocoaError(.fileWriteNoPermission)
        }
        func removeString(forKey key: String) throws {}
    }

    private struct Fixture {
        let directory: URL
        let snapshotURL: URL
        let vectorURL: URL
        let secrets: MemorySecretStore
        let repository: NottiMemoryRepository
    }

    private actor CapturingExtractor: NottiMemoryExtracting {
        private(set) var jobs: [NottiMemoryExtractionJob] = []

        func extract(
            job: NottiMemoryExtractionJob,
            candidates: [NottiMemoryExtractionCandidate]
        ) async throws -> [NottiMemoryProposal] {
            jobs.append(job)
            return []
        }
    }

    private struct StubEmbeddingService: EmbeddingService {
        let modelIdentifier = "test-memory-embedding"

        func embed(_ text: String) async throws -> [Float] {
            [1, 0]
        }
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notti-memory-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("notti_memory_v1.enc")
        let vectorURL = directory.appendingPathComponent("notti_memory_vectors_v1.enc")
        let secrets = MemorySecretStore()
        return Fixture(
            directory: directory,
            snapshotURL: snapshotURL,
            vectorURL: vectorURL,
            secrets: secrets,
            repository: NottiMemoryRepository(
                snapshotURL: snapshotURL,
                vectorURL: vectorURL,
                secretStore: secrets
            )
        )
    }

    private func replaceFileWithDirectory(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    private func proposal(
        text: String,
        category: NottiMemoryCategory = .preference,
        durability: NottiMemoryDurability = .stable,
        topicKey: String = "preference.drink",
        entities: [String] = [],
        keywords: [String] = [],
        expiresAt: Date? = nil,
        evidenceQuote: String? = nil,
        relatedMemoryID: UUID? = nil,
        relationship: NottiMemoryProposalRelationship = .none
    ) -> NottiMemoryProposal {
        NottiMemoryProposal(
            text: text,
            category: category,
            durability: durability,
            topicKey: topicKey,
            entities: entities,
            keywords: keywords,
            expiresAt: expiresAt,
            evidenceQuote: evidenceQuote ?? text,
            relatedMemoryID: relatedMemoryID,
            relationship: relationship
        )
    }

    func testEncryptedSnapshotRoundTripDoesNotExposePlaintext() async throws {
        let fixture = try makeFixture()
        let text = "我喜欢手冲咖啡"
        _ = try await fixture.repository.applyProposals(
            [proposal(text: text)],
            sourceMessageID: UUID(),
            sourceText: text
        )

        let ciphertext = try Data(contentsOf: fixture.snapshotURL)
        XCTAssertNil(String(data: ciphertext, encoding: .utf8)?.range(of: text))

        let reopened = NottiMemoryRepository(
            snapshotURL: fixture.snapshotURL,
            vectorURL: fixture.vectorURL,
            secretStore: fixture.secrets
        )
        let memories = try await reopened.allMemories()
        XCTAssertEqual(memories.map(\.text), [text])
    }

    func testMissingKeyDoesNotOverwriteExistingCiphertext() async throws {
        let fixture = try makeFixture()
        let text = "我喜欢乌龙茶"
        _ = try await fixture.repository.applyProposals(
            [proposal(text: text)],
            sourceMessageID: UUID(),
            sourceText: text
        )
        let original = try Data(contentsOf: fixture.snapshotURL)

        let unavailable = NottiMemoryRepository(
            snapshotURL: fixture.snapshotURL,
            vectorURL: fixture.vectorURL,
            secretStore: MemorySecretStore()
        )
        do {
            _ = try await unavailable.allMemories()
            XCTFail("Expected an unavailable encrypted repository")
        } catch {
            XCTAssertTrue(
                error as? NottiMemoryRepositoryError == .keyUnavailable ||
                error as? NottiMemoryRepositoryError == .invalidCiphertext
            )
        }
        XCTAssertEqual(try Data(contentsOf: fixture.snapshotURL), original)
    }

    func testCorruptVectorSidecarRequestsRebuildWithoutLosingMemories() async throws {
        let fixture = try makeFixture()
        let text = "我偏好安静的工作环境"
        let result = try await fixture.repository.applyProposals(
            [proposal(text: text)],
            sourceMessageID: UUID(),
            sourceText: text
        )
        guard case let .added(memoryID) = try XCTUnwrap(result.first) else {
            return XCTFail("Expected a new memory")
        }
        try await fixture.repository.setVector(
            NottiMemoryVector(vector: [1, 0], model: "test", contentHash: NottiMemoryRepository.contentHash(text)),
            for: memoryID
        )
        try Data("corrupt".utf8).write(to: fixture.vectorURL, options: .atomic)

        let reopened = NottiMemoryRepository(
            snapshotURL: fixture.snapshotURL,
            vectorURL: fixture.vectorURL,
            secretStore: fixture.secrets
        )
        let reopenedMemories = try await reopened.allMemories()
        let missingVectorIDs = try await reopened.memoryIDsNeedingVectors(model: "test")
        let vectorNeedsRebuild = await reopened.vectorNeedsRebuild
        XCTAssertEqual(reopenedMemories.count, 1)
        XCTAssertEqual(missingVectorIDs, [memoryID])
        XCTAssertTrue(vectorNeedsRebuild)
    }

    func testThreeDistinctMentionsProduceOneMemoryWithThreeEvidence() async throws {
        let fixture = try makeFixture()
        let fact = "我喜欢喝拿铁"
        for _ in 0..<3 {
            _ = try await fixture.repository.applyProposals(
                [proposal(text: fact)],
                sourceMessageID: UUID(),
                sourceText: fact
            )
        }
        let memories = try await fixture.repository.allMemories()
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories[0].status, .active)
        XCTAssertEqual(memories[0].evidenceCount, 3)
        XCTAssertEqual(memories[0].evidence.count, 3)
    }

    func testPatternNeedsTwoDistinctMessagesToActivate() async throws {
        let fixture = try makeFixture()
        let fact = "我每周五都会复盘"
        let messageID = UUID()
        let pattern = proposal(
            text: fact,
            category: .pattern,
            durability: .stable,
            topicKey: "pattern.weekly-review"
        )
        _ = try await fixture.repository.applyProposals([pattern], sourceMessageID: messageID, sourceText: fact)
        _ = try await fixture.repository.applyProposals([pattern], sourceMessageID: messageID, sourceText: fact)
        let repeatedMemory = try await fixture.repository.allMemories().first
        XCTAssertEqual(repeatedMemory?.status, .provisional)

        _ = try await fixture.repository.applyProposals([pattern], sourceMessageID: UUID(), sourceText: fact)
        let activatedMemory = try await fixture.repository.allMemories().first
        let memory = try XCTUnwrap(activatedMemory)
        XCTAssertEqual(memory.status, .active)
        XCTAssertEqual(memory.evidenceCount, 2)
    }

    func testSensitiveMemoryWaitsForConfirmationAndSecretsAreRejected() async throws {
        let fixture = try makeFixture()
        let sensitiveText = "我的家庭住址是上海市静安区某路 10 号"
        let pending = try await fixture.repository.applyProposals(
            [proposal(text: sensitiveText, category: .profile, topicKey: "profile.address")],
            sourceMessageID: UUID(),
            sourceText: sensitiveText
        )
        guard case let .pending(pendingID) = try XCTUnwrap(pending.first) else {
            return XCTFail("Expected sensitive memory confirmation")
        }
        let memoriesBeforeConfirmation = try await fixture.repository.allMemories()
        let pendingBeforeConfirmation = try await fixture.repository.pendingMemories()
        XCTAssertTrue(memoriesBeforeConfirmation.isEmpty)
        XCTAssertEqual(pendingBeforeConfirmation.count, 1)
        _ = try await fixture.repository.confirmPending(id: pendingID)
        let confirmedMemory = try await fixture.repository.allMemories().first
        XCTAssertEqual(confirmedMemory?.privacy, .sensitive)

        let secret = "我的 API Key: sk-1234567890abcdefgh"
        let rejected = try await fixture.repository.applyProposals(
            [proposal(text: secret, category: .profile, topicKey: "profile.secret")],
            sourceMessageID: UUID(),
            sourceText: secret
        )
        guard case let .rejected(reason) = try XCTUnwrap(rejected.first) else {
            return XCTFail("Expected forbidden secret rejection")
        }
        XCTAssertEqual(reason, "forbidden secret")
    }

    func testExplicitRememberRequestActivatesSensitiveMemoryAndClearsMatchingPending() async throws {
        let fixture = try makeFixture()
        let sensitiveText = "我的家庭住址是上海市静安区某路 10 号"
        let sensitiveProposal = proposal(
            text: sensitiveText,
            category: .profile,
            topicKey: "profile.address"
        )
        let pendingResult = try await fixture.repository.applyProposals(
            [sensitiveProposal],
            sourceMessageID: UUID(),
            sourceText: sensitiveText
        )
        guard case .pending = try XCTUnwrap(pendingResult.first) else {
            return XCTFail("Expected sensitive memory confirmation")
        }

        let explicitResult = try await fixture.repository.applyProposals(
            [sensitiveProposal],
            sourceMessageID: UUID(),
            sourceText: "请记住，\(sensitiveText)"
        )

        guard case .added = try XCTUnwrap(explicitResult.first) else {
            return XCTFail("Expected explicitly requested sensitive memory to activate")
        }
        let pendingAfterExplicitRequest = try await fixture.repository.pendingMemories()
        let memoriesAfterExplicitRequest = try await fixture.repository.allMemories()
        XCTAssertTrue(pendingAfterExplicitRequest.isEmpty)
        XCTAssertEqual(memoriesAfterExplicitRequest.count, 1)
        XCTAssertEqual(memoriesAfterExplicitRequest.first?.status, .active)
        XCTAssertEqual(memoriesAfterExplicitRequest.first?.privacy, .sensitive)
    }

    func testFailedSnapshotMutationsRestoreMemoryPendingQueueAndAccessState() async throws {
        let fixture = try makeFixture()
        let now = Date(timeIntervalSince1970: 20_000_000)
        let text = "我喜欢手冲咖啡"
        let added = try await fixture.repository.applyProposals(
            [proposal(text: text)],
            sourceMessageID: UUID(),
            sourceText: text,
            now: now
        )
        guard case let .added(memoryID) = try XCTUnwrap(added.first) else {
            return XCTFail("Expected a memory")
        }
        let sensitiveText = "我的家庭住址是上海市静安区某路 10 号"
        let pendingResult = try await fixture.repository.applyProposals(
            [proposal(text: sensitiveText, category: .profile, topicKey: "profile.address")],
            sourceMessageID: UUID(),
            sourceText: sensitiveText,
            now: now
        )
        guard case let .pending(pendingID) = try XCTUnwrap(pendingResult.first) else {
            return XCTFail("Expected a pending memory")
        }
        let jobID = try await fixture.repository.enqueueExtraction(
            userMessageID: UUID(),
            userMessage: "我喜欢拿铁",
            now: now
        )
        let memoriesBeforeFailure = try await fixture.repository.allMemories(now: now)
        let pendingBeforeFailure = try await fixture.repository.pendingMemories()
        let jobBeforeFailure = try await fixture.repository.nextExtractionJob(now: now)
        try replaceFileWithDirectory(at: fixture.snapshotURL)

        do {
            _ = try await fixture.repository.applyProposals(
                [proposal(text: "我喜欢红茶", topicKey: "preference.tea")],
                sourceMessageID: UUID(),
                sourceText: "我喜欢红茶",
                now: now
            )
            XCTFail("Expected snapshot persistence to fail")
        } catch {}
        do {
            try await fixture.repository.touch(ids: [memoryID], at: now.addingTimeInterval(1))
            XCTFail("Expected touch persistence to fail")
        } catch {}
        do {
            try await fixture.repository.rejectPending(id: pendingID)
            XCTFail("Expected pending rejection persistence to fail")
        } catch {}
        do {
            try await fixture.repository.markExtractionFailure(jobID: jobID, now: now)
            XCTFail("Expected queue persistence to fail")
        } catch {}

        let memoriesAfterFailure = try await fixture.repository.allMemories(now: now)
        let pendingAfterFailure = try await fixture.repository.pendingMemories()
        let jobAfterFailure = try await fixture.repository.nextExtractionJob(now: now)
        XCTAssertEqual(memoriesAfterFailure, memoriesBeforeFailure)
        XCTAssertEqual(pendingAfterFailure, pendingBeforeFailure)
        XCTAssertEqual(jobAfterFailure, jobBeforeFailure)
    }

    func testFailedVectorMutationRestoresVectorAndRebuildFlag() async throws {
        let fixture = try makeFixture()
        let text = "我喜欢手冲咖啡"
        let added = try await fixture.repository.applyProposals(
            [proposal(text: text)],
            sourceMessageID: UUID(),
            sourceText: text
        )
        guard case let .added(memoryID) = try XCTUnwrap(added.first) else {
            return XCTFail("Expected a memory")
        }
        try await fixture.repository.setVector(
            NottiMemoryVector(
                vector: [1, 0],
                model: "baseline-model",
                contentHash: NottiMemoryRepository.contentHash(text)
            ),
            for: memoryID
        )
        let needsBaselineBeforeFailure = try await fixture.repository.memoryIDsNeedingVectors(
            model: "baseline-model"
        )
        let rebuildBeforeFailure = await fixture.repository.vectorNeedsRebuild
        try replaceFileWithDirectory(at: fixture.vectorURL)

        do {
            try await fixture.repository.setVector(
                NottiMemoryVector(
                    vector: [0, 1],
                    model: "replacement-model",
                    contentHash: NottiMemoryRepository.contentHash(text)
                ),
                for: memoryID
            )
            XCTFail("Expected vector persistence to fail")
        } catch {}

        let needsBaselineAfterFailure = try await fixture.repository.memoryIDsNeedingVectors(
            model: "baseline-model"
        )
        let needsReplacementAfterFailure = try await fixture.repository.memoryIDsNeedingVectors(
            model: "replacement-model"
        )
        let rebuildAfterFailure = await fixture.repository.vectorNeedsRebuild
        XCTAssertEqual(needsBaselineAfterFailure, needsBaselineBeforeFailure)
        XCTAssertEqual(needsReplacementAfterFailure, [memoryID])
        XCTAssertEqual(rebuildAfterFailure, rebuildBeforeFailure)
    }

    func testSupersedeArchivesOldFactAndHardDeleteRemovesLinks() async throws {
        let fixture = try makeFixture()
        let oldText = "我住在北京"
        let added = try await fixture.repository.applyProposals(
            [proposal(text: oldText, category: .profile, topicKey: "profile.city")],
            sourceMessageID: UUID(),
            sourceText: oldText
        )
        guard case let .added(oldID) = try XCTUnwrap(added.first) else {
            return XCTFail("Expected old fact")
        }
        let newText = "我现在住在上海"
        let resolutions = try await fixture.repository.applyProposals(
            [proposal(
                text: newText,
                category: .profile,
                topicKey: "profile.city",
                relatedMemoryID: oldID,
                relationship: .supersede
            )],
            sourceMessageID: UUID(),
            sourceText: newText
        )
        guard case let .superseded(_, newID) = try XCTUnwrap(resolutions.first) else {
            return XCTFail("Expected supersede")
        }
        let supersededMemory = try await fixture.repository.memory(id: oldID)
        let replacementMemory = try await fixture.repository.memory(id: newID)
        XCTAssertEqual(supersededMemory?.status, .superseded)
        XCTAssertEqual(replacementMemory?.status, .active)

        try await fixture.repository.hardDelete(id: oldID)
        let deletedMemory = try await fixture.repository.memory(id: oldID)
        let remainingMemory = try await fixture.repository.memory(id: newID)
        XCTAssertNil(deletedMemory)
        XCTAssertTrue(try XCTUnwrap(remainingMemory).links.isEmpty)
    }

    func testHardDeletePersistsCompleteSnapshotAndVectorRemovalAcrossReload() async throws {
        let fixture = try makeFixture()
        let oldText = "我住在北京"
        let oldResult = try await fixture.repository.applyProposals(
            [proposal(text: oldText, category: .profile, topicKey: "profile.city")],
            sourceMessageID: UUID(),
            sourceText: oldText
        )
        guard case let .added(oldID) = try XCTUnwrap(oldResult.first) else {
            return XCTFail("Expected old memory")
        }
        try await fixture.repository.setVector(
            NottiMemoryVector(
                vector: [1, 0],
                model: "test-memory-embedding",
                contentHash: NottiMemoryRepository.contentHash(oldText)
            ),
            for: oldID
        )

        let newText = "我现在住在上海"
        let newResult = try await fixture.repository.applyProposals(
            [proposal(
                text: newText,
                category: .profile,
                topicKey: "profile.city",
                relatedMemoryID: oldID,
                relationship: .supersede
            )],
            sourceMessageID: UUID(),
            sourceText: newText
        )
        guard case let .superseded(_, newID) = try XCTUnwrap(newResult.first) else {
            return XCTFail("Expected supersede")
        }
        try await fixture.repository.setVector(
            NottiMemoryVector(
                vector: [0, 1],
                model: "test-memory-embedding",
                contentHash: NottiMemoryRepository.contentHash(newText)
            ),
            for: newID
        )

        try await fixture.repository.hardDelete(id: oldID)

        let reopened = NottiMemoryRepository(
            snapshotURL: fixture.snapshotURL,
            vectorURL: fixture.vectorURL,
            secretStore: fixture.secrets
        )
        let reopenedDeletedMemory = try await reopened.memory(id: oldID)
        let reopenedRemainingMemory = try await reopened.memory(id: newID)
        XCTAssertNil(reopenedDeletedMemory)
        let remaining = try XCTUnwrap(reopenedRemainingMemory)
        XCTAssertTrue(remaining.links.isEmpty)

        let encodedKey = try XCTUnwrap(
            fixture.secrets.string(forKey: "notiee.notti.memory.dek.v1")
        )
        let keyData = try XCTUnwrap(Data(base64Encoded: encodedKey))
        let cipher = CryptoService(key: SymmetricKey(data: keyData))
        let snapshotPlaintext = try cipher.decrypt(Data(contentsOf: fixture.snapshotURL))
        let persistedSnapshot = try JSONDecoder().decode(NottiMemorySnapshot.self, from: snapshotPlaintext)
        XCTAssertFalse(persistedSnapshot.memories.contains { $0.id == oldID })
        XCTAssertFalse(persistedSnapshot.memories.contains { memory in
            memory.links.contains { $0.targetID == oldID } ||
                memory.revisions.contains { $0.text == oldText }
        })

        let vectorPlaintext = try cipher.decrypt(Data(contentsOf: fixture.vectorURL))
        let persistedVectors = try JSONDecoder().decode(
            [UUID: NottiMemoryVector].self,
            from: vectorPlaintext
        )
        XCTAssertNil(persistedVectors[oldID])
        XCTAssertNotNil(persistedVectors[newID])
    }

    func testExtractionRejectsRelatedMemoryOutsideJobCandidates() async throws {
        let fixture = try makeFixture()
        let allowedText = "我喜欢美式咖啡"
        let allowed = try await fixture.repository.applyProposals(
            [proposal(text: allowedText, topicKey: "preference.coffee")],
            sourceMessageID: UUID(),
            sourceText: allowedText
        )
        guard case let .added(allowedID) = try XCTUnwrap(allowed.first) else {
            return XCTFail("Expected an allowed candidate memory")
        }

        let protectedText = "我喜欢绿茶"
        let protected = try await fixture.repository.applyProposals(
            [proposal(text: protectedText, topicKey: "preference.tea")],
            sourceMessageID: UUID(),
            sourceText: protectedText
        )
        guard case let .added(protectedID) = try XCTUnwrap(protected.first) else {
            return XCTFail("Expected a protected memory")
        }

        let replacementText = "我现在喜欢红茶"
        let jobID = try await fixture.repository.enqueueExtraction(
            userMessageID: UUID(),
            userMessage: replacementText,
            candidateMemoryIDs: [allowedID]
        )
        let resolutions = try await fixture.repository.completeExtraction(
            jobID: jobID,
            proposals: [proposal(
                text: replacementText,
                topicKey: "preference.tea",
                relatedMemoryID: protectedID,
                relationship: .supersede
            )]
        )

        XCTAssertEqual(resolutions, [.rejected("unauthorized related memory")])
        let protectedStatus = try await fixture.repository.memory(id: protectedID)?.status
        let memoryCount = try await fixture.repository.allMemories().count
        XCTAssertEqual(protectedStatus, .active)
        XCTAssertEqual(memoryCount, 2)
    }

    func testOrthogonalEmbeddingDoesNotRecallUnrelatedMemory() async throws {
        let fixture = try makeFixture()
        let text = "I prefer espresso"
        let added = try await fixture.repository.applyProposals(
            [proposal(text: text, topicKey: "preference.espresso")],
            sourceMessageID: UUID(),
            sourceText: text
        )
        guard case let .added(memoryID) = try XCTUnwrap(added.first) else {
            return XCTFail("Expected a memory")
        }
        try await fixture.repository.setVector(
            NottiMemoryVector(
                vector: [1, 0],
                model: "test-memory-embedding",
                contentHash: NottiMemoryRepository.contentHash(text)
            ),
            for: memoryID
        )

        let recall = try await fixture.repository.search(
            query: "weather forecast",
            embedding: [0, 1],
            embeddingModel: "test-memory-embedding",
            limit: 5
        )

        XCTAssertTrue(recall.results.isEmpty)
        XCTAssertEqual(recall.promptDataBlock, "[]")
    }

    func testCharacterBudgetCountsEncodedJSONDataBlock() async throws {
        let fixture = try makeFixture()
        var rawTextCharacterCount = 0
        for index in 0..<6 {
            let text = "budget-\(index)-" + String(repeating: "\"", count: 390)
            rawTextCharacterCount += text.count
            _ = try await fixture.repository.applyProposals(
                [proposal(text: text, topicKey: "budget.\(index)")],
                sourceMessageID: UUID(),
                sourceText: text
            )
        }
        XCTAssertLessThan(rawTextCharacterCount, 3_000)

        let recall = try await fixture.repository.search(
            query: "budget",
            embedding: nil,
            limit: 10,
            characterBudget: 3_000
        )

        XCTAssertLessThan(recall.results.count, 6)
        XCTAssertLessThanOrEqual(recall.promptDataBlock.count, 3_000)
        let data = try XCTUnwrap(recall.promptDataBlock.data(using: .utf8))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testStaleModelAndContentHashVectorsDoNotParticipateInSemanticRecall() async throws {
        let fixture = try makeFixture()
        let text = "I prefer espresso"
        let added = try await fixture.repository.applyProposals(
            [proposal(text: text, topicKey: "preference.espresso")],
            sourceMessageID: UUID(),
            sourceText: text
        )
        guard case let .added(memoryID) = try XCTUnwrap(added.first) else {
            return XCTFail("Expected a memory")
        }

        try await fixture.repository.setVector(
            NottiMemoryVector(
                vector: [1, 0],
                model: "stale-model",
                contentHash: NottiMemoryRepository.contentHash(text)
            ),
            for: memoryID
        )
        let staleModelRecall = try await fixture.repository.search(
            query: "weather forecast",
            embedding: [1, 0],
            embeddingModel: "current-model",
            limit: 5
        )
        XCTAssertTrue(staleModelRecall.results.isEmpty)

        try await fixture.repository.setVector(
            NottiMemoryVector(
                vector: [1, 0],
                model: "current-model",
                contentHash: NottiMemoryRepository.contentHash("outdated content")
            ),
            for: memoryID
        )
        let staleContentRecall = try await fixture.repository.search(
            query: "weather forecast",
            embedding: [1, 0],
            embeddingModel: "current-model",
            limit: 5
        )
        XCTAssertTrue(staleContentRecall.results.isEmpty)
        let vectorNeedsRebuild = await fixture.repository.vectorNeedsRebuild
        XCTAssertTrue(vectorNeedsRebuild)
    }

    func testRestoringExpiredMemoryClearsExpiryAndMakesItRecallable() async throws {
        let fixture = try makeFixture()
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        let expiresAt = createdAt.addingTimeInterval(86_400)
        let text = "我计划周末整理书房"
        let added = try await fixture.repository.applyProposals(
            [proposal(
                text: text,
                category: .plan,
                durability: .episodic,
                topicKey: "plan.study",
                expiresAt: expiresAt
            )],
            sourceMessageID: UUID(),
            sourceText: text,
            now: createdAt
        )
        guard case let .added(memoryID) = try XCTUnwrap(added.first) else {
            return XCTFail("Expected a memory")
        }

        _ = try await fixture.repository.allMemories(now: expiresAt)
        let expiredStatus = try await fixture.repository.memory(id: memoryID)?.status
        XCTAssertEqual(expiredStatus, .expired)

        try await fixture.repository.setStatus(id: memoryID, status: .active, now: expiresAt)
        let restoredMemory = try await fixture.repository.memory(id: memoryID)
        let restored = try XCTUnwrap(restoredMemory)
        XCTAssertEqual(restored.status, .active)
        XCTAssertNil(restored.expiresAt)

        let recall = try await fixture.repository.search(
            query: "整理书房",
            embedding: nil,
            limit: 5,
            now: expiresAt.addingTimeInterval(1)
        )
        XCTAssertEqual(recall.memoryIDs, [memoryID])
    }

    func testPasswordTokenSpacedCardAndECPrivateKeyAreRejected() async throws {
        let fixture = try makeFixture()
        let secrets = [
            "密码是 hunter2",
            "令牌是 abc",
            "我的银行卡号是 4111 1111 1111 1111",
            "-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEIBogusvalue\n-----END EC PRIVATE KEY-----",
        ]

        for (index, secret) in secrets.enumerated() {
            let resolutions = try await fixture.repository.applyProposals(
                [proposal(
                    text: secret,
                    category: .profile,
                    topicKey: "profile.secret.\(index)"
                )],
                sourceMessageID: UUID(),
                sourceText: secret
            )
            XCTAssertEqual(
                resolutions,
                [.rejected("forbidden secret")],
                "Expected secret to be rejected: \(secret)"
            )
        }
        let memories = try await fixture.repository.allMemories()
        let pending = try await fixture.repository.pendingMemories()
        XCTAssertTrue(memories.isEmpty)
        XCTAssertTrue(pending.isEmpty)
    }

    func testConflictsSupersedeRelationshipEventAndPlanMemories() async throws {
        let fixture = try makeFixture()
        let cases: [(NottiMemoryCategory, String, String, String)] = [
            (.relationship, "relationship.manager", "我的直属经理是 Alice", "我的直属经理是 Bob"),
            (.event, "event.design-review", "设计评审定在周一", "设计评审改到周二"),
            (.plan, "plan.launch", "我计划九月发布", "我计划十月发布"),
        ]

        for (category, topic, oldText, newText) in cases {
            let oldResult = try await fixture.repository.applyProposals(
                [proposal(text: oldText, category: category, topicKey: topic)],
                sourceMessageID: UUID(),
                sourceText: oldText
            )
            guard case let .added(oldID) = try XCTUnwrap(oldResult.first) else {
                return XCTFail("Expected old memory for \(category)")
            }
            let newResult = try await fixture.repository.applyProposals(
                [proposal(text: newText, category: category, topicKey: topic)],
                sourceMessageID: UUID(),
                sourceText: newText
            )
            guard case let .superseded(supersededID, newID) = try XCTUnwrap(newResult.first) else {
                return XCTFail("Expected supersede for \(category)")
            }
            XCTAssertEqual(supersededID, oldID)
            let oldMemory = try await fixture.repository.memory(id: oldID)
            let newMemory = try await fixture.repository.memory(id: newID)
            XCTAssertEqual(oldMemory?.status, .superseded)
            XCTAssertEqual(newMemory?.status, .active)
        }
    }

    func testTransientManualRestoreUsesStatusChangeAsRecentLifecycleSignal() async throws {
        let fixture = try makeFixture()
        let now = Date(timeIntervalSince1970: 9_000_000)
        let createdAt = now.addingTimeInterval(-31 * 86_400)
        let text = "我这周暂时在共享办公室工作"
        let added = try await fixture.repository.applyProposals(
            [proposal(text: text, durability: .transient, topicKey: "state.office")],
            sourceMessageID: UUID(),
            sourceText: text,
            now: createdAt
        )
        guard case let .added(memoryID) = try XCTUnwrap(added.first) else {
            return XCTFail("Expected transient memory")
        }

        _ = try await fixture.repository.allMemories(now: now)
        let archivedMemory = try await fixture.repository.memory(id: memoryID)
        XCTAssertEqual(archivedMemory?.status, .archived)
        try await fixture.repository.setStatus(id: memoryID, status: .active, now: now)
        _ = try await fixture.repository.allMemories(now: now.addingTimeInterval(1))
        let restoredMemory = try await fixture.repository.memory(id: memoryID)
        XCTAssertEqual(restoredMemory?.status, .active)
    }

    func testLegacyReadOnlyFallbackExcludesSensitiveMemoriesAndRejectsWrites() async throws {
        let fixture = try makeFixture()
        let legacy: [String: String] = [
            "饮品偏好": "我喜欢拿铁",
            "健康": "我患有糖尿病",
        ]
        let legacyURL = fixture.directory.appendingPathComponent("spark_memory.json")
        let legacyData = try JSONEncoder().encode(legacy)
        try legacyData.write(to: legacyURL, options: .atomic)
        try Data("corrupt encrypted snapshot".utf8).write(to: fixture.snapshotURL, options: .atomic)

        let isUsingFallback = try await fixture.repository.isUsingLegacyReadOnlyFallback()
        let fallbackMemories = try await fixture.repository.allMemories()
        let fallbackPending = try await fixture.repository.pendingMemories()
        XCTAssertTrue(isUsingFallback)
        XCTAssertEqual(fallbackMemories.map(\.text), ["饮品偏好: 我喜欢拿铁"])
        XCTAssertEqual(fallbackPending.count, 1)
        do {
            _ = try await fixture.repository.applyProposals(
                [self.proposal(text: "我喜欢红茶", topicKey: "preference.tea")],
                sourceMessageID: UUID(),
                sourceText: "我喜欢红茶"
            )
            XCTFail("Legacy fallback must reject writes")
        } catch {
            XCTAssertEqual(error as? NottiMemoryRepositoryError, .unavailable)
        }
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyData)
    }

    func testFailedLegacyBatchImportRollsBackInMemoryState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notti-memory-import-failure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let repository = NottiMemoryRepository(
            snapshotURL: directory.appendingPathComponent("notti_memory_v1.enc"),
            vectorURL: directory.appendingPathComponent("notti_memory_vectors_v1.enc"),
            secretStore: ThrowingSecretStore()
        )
        let text = "饮品偏好: 我喜欢拿铁"
        let item = NottiLegacyMemoryImport(
            proposal: proposal(
                text: text,
                topicKey: "饮品偏好",
                evidenceQuote: "我喜欢拿铁"
            ),
            sourceMessageID: UUID(),
            sourceText: text
        )

        do {
            _ = try await repository.importLegacyMemories([item])
            XCTFail("Expected encrypted batch persistence to fail")
        } catch {
            XCTAssertEqual(error as? NottiMemoryRepositoryError, .keyUnavailable)
        }
        let memoriesAfterFailure = try await repository.allMemories()
        XCTAssertTrue(memoriesAfterFailure.isEmpty)
    }

    func testHybridFallbackTopKBudgetAndTouchSemantics() async throws {
        let fixture = try makeFixture()
        let coffee = "我喜欢埃塞俄比亚手冲咖啡"
        let tea = "我喜欢凤凰单丛乌龙茶"
        _ = try await fixture.repository.applyProposals(
            [proposal(text: coffee, topicKey: "drink.coffee", entities: ["埃塞俄比亚"], keywords: ["咖啡"])],
            sourceMessageID: UUID(),
            sourceText: coffee
        )
        _ = try await fixture.repository.applyProposals(
            [proposal(text: tea, topicKey: "drink.tea", entities: ["凤凰单丛"], keywords: ["乌龙茶"])],
            sourceMessageID: UUID(),
            sourceText: tea
        )

        let recall = try await fixture.repository.search(
            query: "咖啡",
            embedding: nil,
            limit: 1,
            characterBudget: 3_000
        )
        XCTAssertEqual(recall.results.count, 1)
        XCTAssertEqual(recall.results.first?.memory.text, coffee)
        XCTAssertEqual(recall.results.first?.memory.accessTimestamps, [])

        let selectedID = try XCTUnwrap(recall.results.first?.memory.id)
        try await fixture.repository.touch(ids: [selectedID, selectedID], at: Date(timeIntervalSince1970: 100))
        let touchedMemory = try await fixture.repository.memory(id: selectedID)
        XCTAssertEqual(touchedMemory?.accessTimestamps.count, 1)

        let tooSmall = try await fixture.repository.search(
            query: "咖啡",
            embedding: nil,
            limit: 5,
            characterBudget: 2
        )
        XCTAssertTrue(tooSmall.results.isEmpty)
    }

    func testCJKTokenizationPenaltyAndIndependentActivationBoosts() {
        XCTAssertTrue(NottiMemoryRepository.tokenize("机器学习").contains("机器"))
        XCTAssertEqual(NottiMemoryRepository.entityGeneralityPenalty(linkedCount: 1), 1, accuracy: 0.0001)
        XCTAssertLessThan(
            NottiMemoryRepository.entityGeneralityPenalty(linkedCount: 100),
            NottiMemoryRepository.entityGeneralityPenalty(linkedCount: 2)
        )

        let now = Date(timeIntervalSince1970: 10_000_000)
        let evidence = NottiMemoryEvidence(
            sourceMessageID: UUID(),
            source: .user,
            quote: "fact",
            capturedAt: now.addingTimeInterval(-86_400 * 180)
        )
        let base = NottiMemory(
            text: "fact",
            category: .preference,
            durability: .stable,
            status: .active,
            topicKey: "fact",
            evidence: [evidence],
            evidenceCount: 1,
            createdAt: evidence.capturedAt,
            updatedAt: evidence.capturedAt,
            lastEvidenceAt: evidence.capturedAt
        )
        var evidenceBoosted = base
        evidenceBoosted.evidenceCount = 3
        var accessBoosted = base
        accessBoosted.accessTimestamps = [now.addingTimeInterval(-60)]

        let baseActivation = NottiMemoryRepository.activationMultiplier(for: base, now: now)
        XCTAssertGreaterThan(
            NottiMemoryRepository.activationMultiplier(for: evidenceBoosted, now: now),
            baseActivation
        )
        XCTAssertGreaterThan(
            NottiMemoryRepository.activationMultiplier(for: accessBoosted, now: now),
            baseActivation
        )
    }

    func testLegacyMigrationIsIdempotentAndQuarantinesSensitiveItems() async throws {
        let fixture = try makeFixture()
        let defaultsName = "notti-migration-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsName) }
        let legacy: [String: String] = [
            "饮品偏好": "我喜欢拿铁",
            "健康": "我患有糖尿病",
        ]
        try JSONEncoder().encode(legacy).write(
            to: fixture.directory.appendingPathComponent("spark_memory.json"),
            options: .atomic
        )
        let migration = NottiMigrationCoordinator(
            directory: fixture.directory,
            repository: fixture.repository,
            defaults: defaults,
            secretStore: fixture.secrets
        )

        try await migration.migrateLegacyMemory()
        try await migration.migrateLegacyMemory()

        let migratedMemories = try await fixture.repository.allMemories()
        let migratedPending = try await fixture.repository.pendingMemories()
        XCTAssertEqual(migratedMemories.count, 1)
        XCTAssertEqual(migratedMemories.first?.evidenceCount, 1)
        XCTAssertEqual(migratedPending.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.directory.appendingPathComponent("spark_memory.json").path
        ))
        XCTAssertEqual(defaults.integer(forKey: UDK.nottiMemoryMigrationVersion), 1)
    }

    func testPrivacyConsentGatesRecallTouchAndExtraction() async throws {
        let fixture = try makeFixture()
        let fact = "我喜欢喝拿铁"
        let added = try await fixture.repository.applyProposals(
            [proposal(text: fact)],
            sourceMessageID: UUID(),
            sourceText: fact
        )
        guard case let .added(memoryID) = try XCTUnwrap(added.first) else {
            return XCTFail("Expected a memory")
        }
        let defaultsName = "notti-consent-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsName) }
        let extractor = CapturingExtractor()
        let coordinator = NottiMemoryCoordinator(
            repository: fixture.repository,
            extractor: extractor,
            embeddingService: StubEmbeddingService(),
            defaults: defaults,
            networkIsAvailable: { true }
        )
        let touchDate = Date(timeIntervalSince1970: 123_456)

        let blockedRecall = await coordinator.recall(for: "拿铁", now: touchDate)
        await coordinator.recordSuccessfulRound(
            userMessageID: UUID(),
            userMessage: fact,
            confirmedToolResults: ["note_create: 已创建记录"],
            injectedMemoryIDs: [memoryID],
            now: touchDate
        )

        XCTAssertEqual(blockedRecall, .empty)
        let untouched = try await fixture.repository.memory(id: memoryID)
        XCTAssertTrue(try XCTUnwrap(untouched).accessTimestamps.isEmpty)
        let blockedJobs = await extractor.jobs
        XCTAssertTrue(blockedJobs.isEmpty)

        defaults.set(
            NottiMemoryCoordinator.currentPrivacyNoticeVersion,
            forKey: UDK.nottiMemoryPrivacyNoticeVersion
        )
        let allowedRecall = await coordinator.recall(for: "拿铁", now: touchDate)
        await coordinator.recordSuccessfulRound(
            userMessageID: UUID(),
            userMessage: fact,
            confirmedToolResults: ["note_create: 已创建记录"],
            injectedMemoryIDs: [memoryID],
            now: touchDate
        )

        XCTAssertEqual(allowedRecall.memoryIDs, [memoryID])
        let touched = try await fixture.repository.memory(id: memoryID)
        XCTAssertEqual(try XCTUnwrap(touched).accessTimestamps, [touchDate])
        let capturedJobs = await extractor.jobs
        XCTAssertEqual(capturedJobs.count, 1)
        XCTAssertEqual(capturedJobs.first?.confirmedToolResults, ["note_create: 已创建记录"])
    }

    func testOfflineQueueProcessingDoesNotConsumeRetryAttempt() async throws {
        let fixture = try makeFixture()
        let defaultsName = "notti-offline-queue-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set(
            NottiMemoryCoordinator.currentPrivacyNoticeVersion,
            forKey: UDK.nottiMemoryPrivacyNoticeVersion
        )
        let extractor = CapturingExtractor()
        let coordinator = NottiMemoryCoordinator(
            repository: fixture.repository,
            extractor: extractor,
            embeddingService: StubEmbeddingService(),
            defaults: defaults,
            networkIsAvailable: { false }
        )
        let now = Date(timeIntervalSince1970: 500_000)
        _ = try await fixture.repository.enqueueExtraction(
            userMessageID: UUID(),
            userMessage: "我喜欢拿铁",
            now: now
        )

        await coordinator.processQueue(now: now)

        let extractionJobs = await extractor.jobs
        XCTAssertTrue(extractionJobs.isEmpty)
        let queuedJob = try await fixture.repository.nextExtractionJob(now: now)
        let queued = try XCTUnwrap(queuedJob)
        XCTAssertEqual(queued.attempts, 0)
    }

    func testRecallRebuildsMissingVectorsBeforeSemanticSearch() async throws {
        let fixture = try makeFixture()
        let text = "I prefer espresso"
        let added = try await fixture.repository.applyProposals(
            [proposal(text: text, topicKey: "preference.espresso")],
            sourceMessageID: UUID(),
            sourceText: text
        )
        guard case let .added(memoryID) = try XCTUnwrap(added.first) else {
            return XCTFail("Expected a memory")
        }
        let defaultsName = "notti-vector-rebuild-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set(
            NottiMemoryCoordinator.currentPrivacyNoticeVersion,
            forKey: UDK.nottiMemoryPrivacyNoticeVersion
        )
        let coordinator = NottiMemoryCoordinator(
            repository: fixture.repository,
            extractor: CapturingExtractor(),
            embeddingService: StubEmbeddingService(),
            defaults: defaults,
            networkIsAvailable: { true }
        )

        let recall = await coordinator.recall(for: "unrelated lexical query")

        XCTAssertEqual(recall.memoryIDs, [memoryID])
        let missingVectorIDs = try await fixture.repository.memoryIDsNeedingVectors(
            model: "test-memory-embedding"
        )
        XCTAssertTrue(missingVectorIDs.isEmpty)
    }
}
