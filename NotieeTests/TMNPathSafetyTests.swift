import XCTest
@testable import Notiee

@MainActor
final class TMNPathSafetyTests: XCTestCase {
    func testSecureResolve_rejectsTraversal() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tmn-\(UUID())")
        XCTAssertThrowsError(try TMNImportService.secureResolve(base: base, relative: "../../etc/passwd"))
        XCTAssertThrowsError(try TMNImportService.secureResolve(base: base, relative: "../secret.plist"))
    }

    func testSecureResolve_allowsInsidePaths() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tmn-\(UUID())")
        let url = try TMNImportService.secureResolve(base: base, relative: "images/a.jpg")
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(base.standardizedFileURL.path + "/"))
    }
}
