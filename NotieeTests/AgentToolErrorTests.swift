import XCTest
@testable import Notiee

final class AgentToolErrorTests: XCTestCase {
    func testMissingParameter_hasReadableMessage() {
        let err = AgentToolError.missingParameter("start_date")
        XCTAssertEqual(err.errorDescription, "缺少必要参数：start_date")
    }

    func testSnapshotWriteFailed_hasReadableMessage() {
        XCTAssertEqual(AgentToolError.snapshotWriteFailed.errorDescription, "保存快照失败")
    }
}
