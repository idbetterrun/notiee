import XCTest
@testable import Notiee

final class PersistenceRecoveryTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pr-\(UUID()).json")
    }

    func testLoad_success_returnsValueAndKeepsFile() throws {
        let url = tmpURL()
        try Data("ok".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let value = PersistenceRecovery.loadOrQuarantine(fileURL: url) { "decoded" }

        XCTAssertEqual(value, "decoded")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoad_throws_quarantinesFileAndReturnsNil() throws {
        let url = tmpURL()
        try Data("corrupt".utf8).write(to: url)

        struct Boom: Error {}
        let value: String? = PersistenceRecovery.loadOrQuarantine(fileURL: url) { throw Boom() }

        XCTAssertNil(value)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let siblings = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        XCTAssertTrue(siblings.contains { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".corrupt-") })
    }
}
