import XCTest
@testable import Notiee

@MainActor
final class NewUIPreviewNottiStateTests: XCTestCase {
    func testSubmitAddsOneTurnAndRevealsDeterministicAnswer() {
        let state = makeState()

        state.submit(prompt: "帮我整理今天的记录", startsStreaming: false)

        XCTAssertEqual(state.messages.map(\.role), [.user, .assistant])
        XCTAssertTrue(state.isGenerating)
        XCTAssertFalse(state.messages[1].isComplete)

        state.revealAllPending()

        XCTAssertFalse(state.isGenerating)
        XCTAssertTrue(state.messages[1].isComplete)
        XCTAssertTrue(state.messages[1].content.contains("## 当前重点"))
    }

    func testStopKeepsAlreadyRevealedContent() {
        let state = makeState()
        state.submit(prompt: "分析一下", startsStreaming: false)
        XCTAssertTrue(state.revealNextChunk())
        let partialAnswer = state.messages.last?.content

        state.stopGenerating()

        XCTAssertFalse(state.isGenerating)
        XCTAssertEqual(state.messages.count, 2)
        XCTAssertEqual(state.messages.last?.content, partialAnswer)
        XCTAssertEqual(state.messages.last?.isComplete, true)
    }

    func testCancelledAsyncStreamDoesNotResumeWriting() async throws {
        let state = makeState()
        state.submit(prompt: "异步取消测试")

        try await Task.sleep(nanoseconds: 85_000_000)
        state.stopGenerating()
        let stoppedContent = state.messages.last?.content

        try await Task.sleep(nanoseconds: 180_000_000)

        XCTAssertFalse(state.isGenerating)
        XCTAssertEqual(state.messages.last?.content, stoppedContent)
        XCTAssertEqual(state.messages.last?.isComplete, true)
    }

    func testImmediateStopRemovesOnlyEmptyAssistantPlaceholder() async throws {
        let state = makeState()
        state.submit(prompt: "立即停止")

        state.stopGenerating()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(state.messages.map(\.role), [.user])
        XCTAssertFalse(state.isGenerating)
    }

    func testRegenerateReplacesAssistantAnswerWithoutAddingBranch() {
        let state = makeState()
        state.submit(prompt: "复盘最近的记录", startsStreaming: false)
        state.revealAllPending()
        let originalAssistantID = state.messages[1].id

        state.regenerate(startsStreaming: false)

        XCTAssertEqual(state.messages.count, 2)
        XCTAssertNotEqual(state.messages[1].id, originalAssistantID)
        XCTAssertTrue(state.isGenerating)
        state.revealAllPending()
        XCTAssertEqual(state.messages.count, 2)
    }

    func testWebSearchIsOneShotAndAgentPersistsForConversation() {
        let state = makeState()
        state.webSearchEnabled = true
        state.agentModeEnabled = true

        state.submit(prompt: "查找并整理", startsStreaming: false)

        XCTAssertFalse(state.webSearchEnabled)
        XCTAssertTrue(state.agentModeEnabled)
        state.revealAllPending()
        XCTAssertTrue(state.messages[1].content.contains("已联网检索"))
        XCTAssertTrue(state.messages[1].content.contains("Agent 已规划"))
    }

    func testNewConversationResetsConversationModesButKeepsModel() throws {
        let models = [
            NewUIPreviewNottiModel(id: "first", title: "First"),
            NewUIPreviewNottiModel(id: "second", title: "Second")
        ]
        let state = makeState(models: models)
        state.selectModel("second")
        state.selectedThinking = .deep
        state.webSearchEnabled = true
        state.agentModeEnabled = true
        state.submit(prompt: "测试会话", startsStreaming: false)

        state.newConversation()

        XCTAssertTrue(state.messages.isEmpty)
        XCTAssertEqual(state.conversationTitle, "Notti")
        XCTAssertEqual(state.selectedModelID, "second")
        XCTAssertEqual(state.selectedThinking, .quick)
        XCTAssertFalse(state.webSearchEnabled)
        XCTAssertFalse(state.agentModeEnabled)
    }

    func testDefaultModelCatalogMatchesCurrentProductTarget() {
        let models = NewUIPreviewNottiState.defaultModelOptions

        #if NOTIEE_PLUS
        XCTAssertEqual(models.map(\.id), ["qwen3.5-plus", "deepseek-v4-pro", "MiniMax-M3"])
        #else
        XCTAssertEqual(
            models.map(\.id),
            CuratedModelCatalog.models(kind: .text).map(\.id)
        )
        #endif
    }

    private func makeState(
        models: [NewUIPreviewNottiModel] = [
            NewUIPreviewNottiModel(id: "preview", title: "Preview")
        ]
    ) -> NewUIPreviewNottiState {
        NewUIPreviewNottiState(modelOptions: models)
    }
}
