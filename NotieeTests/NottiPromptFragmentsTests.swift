import XCTest
@testable import Notiee

final class NottiPromptFragmentsTests: XCTestCase {
    func testLanguageRule_containsEnglishAndChineseDirectives() {
        let rule = NottiPromptFragments.languageRule
        XCTAssertTrue(rule.contains("全英文回复"), "应包含英文匹配规则")
        XCTAssertTrue(rule.contains("全中文回复"), "应包含中文匹配规则")
    }

    func testAgentSystemPrompt_includesLanguageRule() {
        let prompt = NottiPromptFragments.agentSystemPrompt(now: Date())
        XCTAssertTrue(prompt.contains(NottiPromptFragments.languageRule),
                      "Agent 系统提示词必须包含语言匹配规则")
    }

    func testAgentPrompt_allowsUserOwnDataRetrieval() {
        let p = NottiPromptFragments.agentSystemPrompt(now: Date())
        XCTAssertTrue(p.contains("用户自己"), "应包含'用户自己的数据可检索'语义")
        XCTAssertTrue(p.contains("API Key"), "仍保护 API Key")
    }
}
