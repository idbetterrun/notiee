import XCTest
@testable import Notiee

final class NottiIntentDetectorTests: XCTestCase {
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
            XCTAssertTrue(NottiIntentDetector.looksLikeActionRequest(s), "应判定为动作请求: \(s)")
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
            XCTAssertFalse(NottiIntentDetector.looksLikeActionRequest(s), "不应判定为动作请求: \(s)")
        }
    }

    func testShortFollowup_detected() {
        let yes = [
            "翻译一下",
            "展开说说",
            "详细讲讲",
            "继续说",
            "然后呢",
            "这篇呢",
            "这个详细",
            "translate this",
            "elaborate",
            "continue",
            "更多细节",
            "接着说",
        ]
        for s in yes {
            XCTAssertTrue(NottiIntentDetector.isShortFollowup(s), "应判定为短跟进: \(s)")
        }
    }

    func testShortFollowup_notDetected_normalQuestions() {
        let no = [
            "今天天气怎么样",
            "你是谁",
            "帮我回顾一下最近的笔记",
            "这个人是谁拍的",
        ]
        for s in no {
            XCTAssertFalse(NottiIntentDetector.isShortFollowup(s), "不应判定为短跟进: \(s)")
        }
    }

    func testShortFollowup_notDetected_longMessage() {
        let long = "请帮我把刚才提到的那篇文章翻译成中文"
        XCTAssertFalse(NottiIntentDetector.isShortFollowup(long), "长消息不应触发短跟进")
    }
}
