import XCTest
@testable import Notiee

final class SparkCitationStripTests: XCTestCase {
    func testStripsSingleAndMultipleMarkers() {
        XCTAssertEqual(
            SparkAIService.stripCitationMarkers("根据[来源1]会议纪要和[来源3]读书笔记，本周重点是交付。"),
            "根据会议纪要和读书笔记，本周重点是交付。")
    }
    func testStripsTrailingClusterAndTrims() {
        XCTAssertEqual(
            SparkAIService.stripCitationMarkers("你下周空得很 [来源2][来源3][来源4]"),
            "你下周空得很")
    }
    func testNoMarkers_unchanged() {
        XCTAssertEqual(SparkAIService.stripCitationMarkers("普通文本"), "普通文本")
    }
}
