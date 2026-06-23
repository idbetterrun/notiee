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
}
