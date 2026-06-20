import XCTest
@testable import Notiee

final class AgentToolPresentationTests: XCTestCase {
    func testKnownTool_hasFriendlyMetadata() {
        let p = AgentToolPresentation.forName("calendar_query")
        XCTAssertEqual(p.icon, "calendar")
        XCTAssertFalse(p.displayName.isEmpty)
        XCTAssertTrue(p.runningText.contains("日程"))
    }

    func testUnknownTool_fallsBackGracefully() {
        let p = AgentToolPresentation.forName("totally_unknown_tool")
        XCTAssertEqual(p.icon, "wrench.and.screwdriver")
        XCTAssertEqual(p.displayName, "totally_unknown_tool")
    }
}
