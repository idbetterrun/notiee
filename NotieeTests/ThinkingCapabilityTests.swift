import XCTest
@testable import Notiee

final class ThinkingCapabilityTests: XCTestCase {
    func testDoubao_hasEffortLevels() {
        let cap = ThinkingCapability.forProvider(.doubaoText)
        XCTAssertFalse(cap.levels.isEmpty)
    }

    func testDoubao_applyHighInjectsReasoningEffort() {
        let cap = ThinkingCapability.forProvider(.doubaoText)
        guard let high = cap.levels.first(where: { $0.id == "high" }) else { return XCTFail("缺 high") }
        var payload: [String: Any] = ["model": "x"]
        cap.apply(level: high, to: &payload)
        XCTAssertEqual(payload["reasoning_effort"] as? String, "high")
    }

    func testQwen_applyOnInjectsEnableThinking() {
        let cap = ThinkingCapability.forProvider(.qwenText)
        guard let on = cap.levels.first(where: { $0.id != "off" }) else { return XCTFail("缺 on 档") }
        var payload: [String: Any] = ["model": "x"]
        cap.apply(level: on, to: &payload)
        XCTAssertEqual(payload["enable_thinking"] as? Bool, true)
    }

    func testQwen_applyOffDisablesThinking() {
        let cap = ThinkingCapability.forProvider(.qwenText)
        guard let off = cap.levels.first(where: { $0.id == "off" }) else { return XCTFail("缺 off") }
        var payload: [String: Any] = [:]
        cap.apply(level: off, to: &payload)
        XCTAssertEqual(payload["enable_thinking"] as? Bool, false)
    }

    func testVision_noThinking() {
        XCTAssertTrue(ThinkingCapability.forProvider(.qwenVision).levels.isEmpty)
    }
}
