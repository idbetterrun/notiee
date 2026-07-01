import XCTest
@testable import Notiee

final class HybridEmbeddingServiceTests: XCTestCase {
    private final class Tagged: EmbeddingService {
        let modelIdentifier: String
        let value: [Float]
        let shouldThrow: Bool
        init(_ id: String, _ v: [Float], throws t: Bool = false) { modelIdentifier = id; value = v; shouldThrow = t }
        func embed(_ text: String) async throws -> [Float] {
            if shouldThrow { throw EmbeddingError.requestFailed("boom") }
            return value
        }
    }

    func testPrefersCloudWhenEnabled() async throws {
        let h = HybridEmbeddingService(local: Tagged("local", [1]), cloud: Tagged("cloud", [2]), preferCloud: { true })
        let v = try await h.embed("x")
        XCTAssertEqual(v, [2])
    }

    func testUsesLocalWhenDisabled() async throws {
        let h = HybridEmbeddingService(local: Tagged("local", [1]), cloud: Tagged("cloud", [2]), preferCloud: { false })
        let v = try await h.embed("x")
        XCTAssertEqual(v, [1])
    }

    func testCloudFailure_fallsBackToLocal() async throws {
        let h = HybridEmbeddingService(local: Tagged("local", [1]), cloud: Tagged("cloud", [2], throws: true), preferCloud: { true })
        let v = try await h.embed("x")
        XCTAssertEqual(v, [1])
    }

    func testNoCloud_usesLocal() async throws {
        let h = HybridEmbeddingService(local: Tagged("local", [9]), cloud: nil, preferCloud: { true })
        let v = try await h.embed("x")
        XCTAssertEqual(v, [9])
    }

    // MARK: - embedTagged 来源标签

    private struct StubEmbed: EmbeddingService {
        let modelIdentifier: String
        let result: [Float]?
        func embed(_ text: String) async throws -> [Float] {
            guard let r = result else { throw EmbeddingError.cannotEmbed }
            return r
        }
    }

    func testEmbedTagged_cloudSuccess_tagsCloudModel() async throws {
        let hybrid = HybridEmbeddingService(
            local: StubEmbed(modelIdentifier: "local", result: [0, 0]),
            cloud: StubEmbed(modelIdentifier: "cloud-x", result: [1, 2, 3]),
            preferCloud: { true })
        let out = try await hybrid.embedTagged("hi")
        XCTAssertEqual(out.model, "cloud-x")
        XCTAssertEqual(out.vector, [1, 2, 3])
    }

    func testEmbedTagged_cloudFails_tagsLocalModel() async throws {
        let hybrid = HybridEmbeddingService(
            local: StubEmbed(modelIdentifier: "local", result: [0, 0]),
            cloud: StubEmbed(modelIdentifier: "cloud-x", result: nil),
            preferCloud: { true })
        let out = try await hybrid.embedTagged("hi")
        XCTAssertEqual(out.model, "local", "fallback 到本地时必须打本地标签，不能仍写 cloud-*")
        XCTAssertEqual(out.vector, [0, 0])
    }
}
