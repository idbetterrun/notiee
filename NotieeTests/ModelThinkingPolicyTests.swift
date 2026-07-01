import XCTest
@testable import Notiee

final class ModelThinkingPolicyTests: XCTestCase {
    func testDeepseekV4Pro_forcesThinkingOn() {
        XCTAssertEqual(
            ModelThinkingPolicy.forcedThinkingLevelID(provider: .deepseek, model: "deepseek-v4-pro"),
            "on"
        )
    }

    func testDeepseekOtherModel_notForced() {
        XCTAssertNil(
            ModelThinkingPolicy.forcedThinkingLevelID(provider: .deepseek, model: "deepseek-chat")
        )
    }

    func testNonDeepseekProvider_notForced() {
        XCTAssertNil(
            ModelThinkingPolicy.forcedThinkingLevelID(provider: .qwenText, model: "deepseek-v4-pro")
        )
    }
}
