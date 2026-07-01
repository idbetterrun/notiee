import XCTest
@testable import Notiee

final class SparkIntentDetectorTests: XCTestCase {
    func testActionRequests_detected() {
        let yes = [
            "帮我创建一个明天的日程",
            "提醒我下午三点开会",
            "记一条待办：买牛奶",
            "Create a schedule for tomorrow 7pm",
            "remind me to call mom",
            "add a todo for the gym",
        ]
        for s in yes {
            XCTAssertTrue(SparkIntentDetector.looksLikeActionRequest(s), "应判定为动作请求: \(s)")
        }
    }

    func testQuestions_notDetected() {
        let no = [
            "今天天气怎么样",
            "你是谁",
            "What is the capital of France?",
            "帮我回顾一下最近的笔记",
        ]
        for s in no {
            XCTAssertFalse(SparkIntentDetector.looksLikeActionRequest(s), "不应判定为动作请求: \(s)")
        }
    }
}
