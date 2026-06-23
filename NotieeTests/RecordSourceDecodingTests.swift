import XCTest
@testable import Notiee

final class RecordSourceDecodingTests: XCTestCase {

    func testLegacyRecordDecodesAsPhoto() throws {
        let legacyJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "capturedAt": 730000000,
            "localImagePaths": ["a.jpg"],
            "title": "Legacy",
            "ocrText": "",
            "summary": "",
            "detailedContent": "",
            "processingState": "completed",
            "keyPoints": [],
            "definitions": [],
            "isFavorite": false,
            "isDeleted": false,
            "tokenUsage": 0,
            "aiRetryCount": 0
        }
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(NoteRecord.self, from: legacyJSON)
        XCTAssertEqual(record.source, .photo)
        XCTAssertEqual(record.title, "Legacy")
    }

    func testSparkRecordRoundTrips() throws {
        let original = NoteRecord(localImagePaths: [], title: "S", source: .spark)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NoteRecord.self, from: data)
        XCTAssertEqual(decoded.source, .spark)
    }
}
