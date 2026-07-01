import XCTest
import CryptoKit
@testable import Notiee

final class CryptoServiceTests: XCTestCase {
    private var svc: CryptoService!

    override func setUp() {
        super.setUp()
        // In-memory key so tests don't touch the real Keychain.
        svc = CryptoService(key: SymmetricKey(size: .bits256))
    }

    func testDataRoundTrip() throws {
        let plain = Data("한국어 secret 机密".utf8)
        let cipher = try svc.encrypt(plain)
        XCTAssertNotEqual(cipher, plain)
        XCTAssertEqual(try svc.decrypt(cipher), plain)
    }

    func testStringRoundTrip() throws {
        let s = "summary text 摘要"
        XCTAssertEqual(try svc.decryptString(svc.encryptString(s)), s)
    }

    func testPasscodeHashVerifies() {
        let salt = CryptoService.makeSalt()
        let hash = CryptoService.hashPasscode("123456", salt: salt)
        XCTAssertTrue(CryptoService.verifyPasscode("123456", salt: salt, expectedHash: hash))
        XCTAssertFalse(CryptoService.verifyPasscode("000000", salt: salt, expectedHash: hash))
    }
}
