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

    func testNottiRecordRoundTrips() throws {
        let original = NoteRecord(localImagePaths: [], title: "S", source: .notti)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NoteRecord.self, from: data)
        XCTAssertEqual(decoded.source, .notti)
    }

    func testLegacySparkSourceDecodesAsNottiAndKeepsStableEncoding() throws {
        XCTAssertEqual(try JSONDecoder().decode(RecordSource.self, from: Data(#""spark""#.utf8)), .notti)
        XCTAssertEqual(try JSONDecoder().decode(RecordSource.self, from: Data(#""notti""#.utf8)), .notti)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(RecordSource.notti), as: UTF8.self), #""spark""#)
    }

    func testLegacySparkTabDecodesAsNottiAndKeepsStableEncoding() throws {
        XCTAssertEqual(try JSONDecoder().decode(AppTab.self, from: Data(#""spark""#.utf8)), .notti)
        XCTAssertEqual(try JSONDecoder().decode(AppTab.self, from: Data(#""notti""#.utf8)), .notti)
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(AppTab.notti), as: UTF8.self), #""spark""#)
    }
}
