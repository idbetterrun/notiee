import XCTest
import CryptoKit
@testable import Notiee

@MainActor
final class SecureRecordCodecTests: XCTestCase {
    func testEncryptThenDecryptRestoresText() throws {
        let crypto = CryptoService(key: SymmetricKey(size: .bits256))
        let codec = SecureRecordCodec(crypto: crypto)

        var record = NoteRecord(localImagePaths: [], title: "My Title")
        record.ocrText = "raw ocr"
        record.summary = "the summary"
        record.detailedContent = "detail body"
        record.keyPoints = ["a", "b"]

        let todos = [NoteTodo(recordID: record.id, content: "buy milk")]

        let (encRecord, blob) = try codec.encrypt(record: record, todos: todos)
        XCTAssertTrue(encRecord.isEncrypted)
        XCTAssertEqual(encRecord.ocrText, "")
        XCTAssertEqual(encRecord.summary, "")
        XCTAssertEqual(encRecord.keyPoints, [])
        XCTAssertNotEqual(encRecord.title, "My Title") // placeholder

        let (decRecord, decTodos) = try codec.decrypt(record: encRecord, blob: blob)
        XCTAssertFalse(decRecord.isEncrypted)
        XCTAssertEqual(decRecord.title, "My Title")
        XCTAssertEqual(decRecord.summary, "the summary")
        XCTAssertEqual(decRecord.keyPoints, ["a", "b"])
        XCTAssertEqual(decTodos.map(\.content), ["buy milk"])
    }
}
