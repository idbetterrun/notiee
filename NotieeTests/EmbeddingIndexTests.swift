import XCTest
@testable import Notiee

@MainActor
final class EmbeddingIndexTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("emb-\(UUID()).json")
    }

    func testSetGet_roundTrips() {
        let url = tmpURL()
        let index = EmbeddingIndex(fileURL: url)
        let id = UUID()
        let entry = EmbeddingEntry(vector: [0.1, 0.2], model: "m1", contentHash: "h1")
        index.set(entry, for: id)
        XCTAssertEqual(index.entry(for: id), entry)
    }

    func testPersistenceAcrossInstances() {
        let url = tmpURL()
        let id = UUID()
        let a = EmbeddingIndex(fileURL: url)
        a.set(EmbeddingEntry(vector: [1, 2, 3], model: "m1", contentHash: "h1"), for: id)
        let b = EmbeddingIndex(fileURL: url)
        XCTAssertEqual(b.entry(for: id)?.vector, [1, 2, 3])
    }

    func testRemove() {
        let url = tmpURL()
        let index = EmbeddingIndex(fileURL: url)
        let id = UUID()
        index.set(EmbeddingEntry(vector: [1], model: "m", contentHash: "h"), for: id)
        index.remove(id: id)
        XCTAssertNil(index.entry(for: id))
    }
}
