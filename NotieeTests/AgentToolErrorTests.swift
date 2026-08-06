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

    func testConfirmedToolSummaryIncludesOnlySuccessfulBoundedResults() {
        let successful = AgentAction(
            toolName: "note_create",
            parameters: [:],
            result: AgentToolResultData(
                success: true,
                message: "已创建项目记录",
                shouldTerminate: false,
                undoAction: nil
            )
        )
        let failed = AgentAction(
            toolName: "schedule_create",
            parameters: [:],
            result: AgentToolResultData(
                success: false,
                message: "权限不足",
                shouldTerminate: false,
                undoAction: nil
            )
        )

        let summary = AgentExecutor.confirmedToolSummary(
            from: [successful, failed],
            characterLimit: 12
        )

        XCTAssertEqual(summary.count, 12)
        XCTAssertTrue(summary.hasPrefix("note_create:"))
        XCTAssertFalse(summary.contains("schedule_create"))
        XCTAssertFalse(summary.contains("权限不足"))
    }

    func testSuccessfulMemorySearchIDsIncludeOnlySuccessfulStructuredResults() throws {
        let firstID = UUID()
        let secondID = UUID()
        let successful = AgentAction(
            toolName: "memory_search",
            parameters: [:],
            result: AgentToolResultData(
                success: true,
                message: "找到两条记忆",
                shouldTerminate: false,
                undoAction: nil,
                dataJSON: """
                {"memories":[{"id":"\(firstID.uuidString)"},{"id":"\(secondID.uuidString)"},{"id":"\(firstID.uuidString)"}]}
                """
            )
        )
        let failed = AgentAction(
            toolName: "memory_search",
            parameters: [:],
            result: AgentToolResultData(
                success: false,
                message: "检索失败",
                shouldTerminate: false,
                undoAction: nil,
                dataJSON: "{\"memories\":[{\"id\":\"\(UUID().uuidString)\"}]}"
            )
        )
        let unrelated = AgentAction(
            toolName: "note_search",
            parameters: [:],
            result: successful.result
        )

        XCTAssertEqual(
            AgentExecutor.successfulMemorySearchIDs(from: [successful, failed, unrelated]),
            [firstID, secondID]
        )
    }
}
