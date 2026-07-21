import XCTest
@testable import Notiee

@MainActor
final class NoteSearchToolTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID()).json")
    }

    private func makeManager(_ titles: [String]) -> RecordManager {
        let records = titles.map { NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: $0) }
        return RecordManager(records: records, todos: [], recordStore: JSONNoteRecordStore(fileURL: tmpURL()))
    }

    func testWithEngine_returnsSemanticMatch() async throws {
        final class StubEngine: SemanticSearching {
            let hitTitle: String
            init(_ t: String) { hitTitle = t }
            func search(query: String, in records: [NoteRecord], limit: Int) async -> [NoteRecord] {
                records.filter { $0.title == hitTitle }
            }
            func backfill(records: [NoteRecord]) async {}
        }
        let mgr = makeManager(["深度学习", "烹饪"])
        let tool = NoteSearchTool(recordManager: mgr, searchEngine: StubEngine("深度学习"))
        let result = try await tool.execute(parameters: ["query": "机器学习"])
        let records = (result.data?["records"] as? [[String: Any]]) ?? []
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?["title"] as? String, "深度学习")
    }

    func testWithoutEngine_keywordPathUnchanged() async throws {
        let mgr = makeManager(["机器学习导论", "烹饪"])
        let tool = NoteSearchTool(recordManager: mgr, searchEngine: nil)
        let result = try await tool.execute(parameters: ["query": "机器学习"])
        let records = (result.data?["records"] as? [[String: Any]]) ?? []
        XCTAssertEqual(records.map { $0["title"] as? String }, ["机器学习导论"])
    }
}
