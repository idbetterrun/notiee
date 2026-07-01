import XCTest
@testable import Notiee

final class AIPromptOutputLanguageTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UDK.labRecordOutputLanguage)
        super.tearDown()
    }

    func testAutoDirectiveMentionsDetectingSourceLanguage() {
        UserDefaults.standard.set("auto", forKey: UDK.labRecordOutputLanguage)
        let d = AIPromptProvider.outputLanguageDirective()
        XCTAssertTrue(d.lowercased().contains("same language"))
        XCTAssertTrue(d.lowercased().contains("detect"))
    }

    func testExplicitDirectiveNamesKorean() {
        UserDefaults.standard.set("ko", forKey: UDK.labRecordOutputLanguage)
        let d = AIPromptProvider.outputLanguageDirective()
        XCTAssertTrue(d.contains("한국어"))
    }

    func testVisionPromptAppendsDirective() {
        UserDefaults.standard.set("ko", forKey: UDK.labRecordOutputLanguage)
        let p = AIPromptProvider.visionPrompt(fullVision: false, latex: false)
        XCTAssertTrue(p.system.contains("한국어"))
        XCTAssertTrue(p.user.contains("한국어"))
    }

    func testTextPromptAppendsDirective() {
        UserDefaults.standard.set("en", forKey: UDK.labRecordOutputLanguage)
        let p = AIPromptProvider.textPrompt(ocrText: "hello", enableSummary: true, enableDetailedContent: true, preset: .college)
        XCTAssertTrue(p.contains("English"))
    }
}
