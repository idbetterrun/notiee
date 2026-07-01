import XCTest
@testable import Notiee

final class NoteRecordEncryptedDecodingTests: XCTestCase {
    func testDecodesLegacyRecordWithoutIsEncryptedAsFalse() throws {
        let record = NoteRecord(localImagePaths: [], title: "t")
        let data = try JSONEncoder().encode(record)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "isEncrypted") // simulate old schema
        let legacy = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(NoteRecord.self, from: legacy)
        XCTAssertFalse(decoded.isEncrypted)
    }

    func testRoundTripEncryptedFlag() throws {
        var r = NoteRecord(localImagePaths: [], title: "x")
        r.isEncrypted = true
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(NoteRecord.self, from: data)
        XCTAssertTrue(decoded.isEncrypted)
    }
}
