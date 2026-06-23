import XCTest
@testable import Notiee

final class LocalEmbeddingServiceTests: XCTestCase {
    func testEnglishSentence_returnsNonEmptyVector_orSkipsIfUnavailable() async throws {
        let svc = LocalEmbeddingService()
        do {
            let v = try await svc.embed("machine learning is fun")
            XCTAssertFalse(v.isEmpty)
        } catch EmbeddingError.unavailable {
            throw XCTSkip("本设备无可用的 NLEmbedding 句向量模型")
        }
    }

    func testModelIdentifierIsStable() {
        XCTAssertEqual(LocalEmbeddingService().modelIdentifier, "nlembedding-sentence-v1")
    }
}
