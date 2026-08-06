import XCTest
@testable import Notiee

final class NottiModelPreferencesTests: XCTestCase {
    private func makePrefs() -> NottiModelPreferences {
        let ud = UserDefaults(suiteName: "test.nottiprefs.\(UUID().uuidString)")!
        return NottiModelPreferences(userDefaults: ud)
    }

    func testEffectiveModel_fallsBackToGlobalWhenNoOverride() {
        let p = makePrefs()
        XCTAssertEqual(p.effectiveModelName(globalModel: "qwen-plus"), "qwen-plus")
    }

    func testEffectiveModel_usesOverride() {
        let p = makePrefs()
        p.setModelOverride("deepseek-v4-pro")
        XCTAssertEqual(p.effectiveModelName(globalModel: "qwen-plus"), "deepseek-v4-pro")
    }

    func testThinkingLevel_persists() {
        let p = makePrefs()
        p.setThinkingLevelID("high")
        XCTAssertEqual(p.thinkingLevelID, "high")
    }

    func testClearOverride_fallsBack() {
        let p = makePrefs()
        p.setModelOverride("x")
        p.setModelOverride("")   // 空视为清除
        XCTAssertEqual(p.effectiveModelName(globalModel: "g"), "g")
    }
}
