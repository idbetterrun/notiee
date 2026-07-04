import XCTest
@testable import Notiee

final class SparkTierLimitsTests: XCTestCase {

    // 测试跑在 Notiee(免费) target，CurrentEntitlement.tier == .free

    func testFreeTierSessionRoundCapIs20() {
        XCTAssertEqual(SparkTierLimits.maxSessionRounds, 20)
    }

    func testFreeTierMemoryCapIs5() {
        XCTAssertEqual(SparkTierLimits.maxMemoryEntries, 5)
    }

    func testFreeTierAgentNotAllowed() {
        XCTAssertFalse(SparkTierLimits.isAgentAllowed)
    }

    func testFreeTierAllowsOnlyFlashText() {
        XCTAssertTrue(SparkTierLimits.isTextModelAllowed("deepseek-v4-flash"))
        XCTAssertFalse(SparkTierLimits.isTextModelAllowed("MiniMax-M3"))
        XCTAssertFalse(SparkTierLimits.isTextModelAllowed("does-not-exist"))
    }

    func testSessionRoundLimitBoundary() {
        XCTAssertFalse(SparkTierLimits.sessionRoundLimitReached(currentRounds: 19))
        XCTAssertTrue(SparkTierLimits.sessionRoundLimitReached(currentRounds: 20))
        XCTAssertTrue(SparkTierLimits.sessionRoundLimitReached(currentRounds: 21))
    }

    func testAcceptedNewMemoryCountClampsToCap() {
        // 已 5 条、还想写 3 条 → 0
        XCTAssertEqual(SparkTierLimits.acceptedNewMemoryCount(existingCount: 5, incoming: 3), 0)
        // 已 3 条、还想写 3 条 → 只收 2（3+2=5 封顶）
        XCTAssertEqual(SparkTierLimits.acceptedNewMemoryCount(existingCount: 3, incoming: 3), 2)
        // 已 0 条、写 4 条 → 全收
        XCTAssertEqual(SparkTierLimits.acceptedNewMemoryCount(existingCount: 0, incoming: 4), 4)
    }
}
