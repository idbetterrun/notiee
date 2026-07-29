# Spark Citation Full-Text Continuation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Let ordinary Spark chat use the immediately preceding assistant reply's cited note bodies on the next user turn, so natural confirmation such as “对，就是这条” can continue translation or explanation without keyword triggers or a second model request.

**Architecture:** SparkViewModel resolves citations from the completed assistant reply before adding the new empty assistant placeholder, validates their IDs against the live record set, and passes them through the existing pinnedRecordIDs parameter. SparkAIService orders bodies by citation ID and limits all injected bodies to 4,000 characters together. The existing main model already receives conversation history and decides whether to use this one-turn candidate context.

**Tech Stack:** Swift 6, SwiftUI, XCTest, existing SparkAIServing and SparkAIService prompt assembly.

**Spec:** docs/superpowers/specs/2026-07-23-spark-citation-fulltext-continuation-design.md

## Global Constraints

- **Target classification:** shared Spark plain-chat code. The change affects both Notiee and Notiee+; do not add a NOTIEE_PLUS conditional.
- Do not change Agent behavior, backend contracts, persistence schema, UI, localization, semantic-recall policy, or model selection.
- Use only the immediately preceding completed assistant message's citations. Never parse titles or model-generated [记录N] to select a record.
- Filter deleted and encrypted records before calling ask with pinnedRecordIDs.
- At most 4,000 body characters total may be injected across all pinned records. Preserve citation order and omit blank bodies.
- No record-selection state may persist after the next assistant response.
- No new Swift files are needed; project.pbxproj must not change.
- Preserve unrelated user-owned worktree changes.
- Prefix Xcode commands with DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer.
- Build both schemes after modifying shared source, using iPhone 17 and CODE_SIGNING_ALLOWED=NO.
- Commit only with separate user authorization. Any authorized commit must include:

~~~text
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
~~~

---

## File Structure

**Modify:**

- Notiee/Features/Spark/SparkViewModel.swift: select immediate-prior citations before placeholder insertion without short-followup keyword gating.
- Notiee/Features/Spark/SparkAIService.swift: order bodies by pinned ID and apply one aggregate body budget.
- NotieeTests/SparkViewModelTests.swift: capture requested pin IDs in MockAIService and add plain-chat continuation/privacy tests.
- NotieeTests/SparkPromptRecallTests.swift: add aggregate-budget and citation-order tests.
- HANDOFF.md: after implementation, record actual test/build results in English.

The existing direct and backend transports already implement this unchanged interface:

~~~swift
func ask(
    question: String,
    recall: RecalledRecords,
    recentRounds: [ConversationRound],
    upcomingEvents: [ScheduledEvent],
    pinnedRecordIDs: [UUID]
) async throws -> (text: String, tokens: Int)
~~~

### Task 1: Resolve Immediate-Prior Citation IDs

**Files:**

- Modify: Notiee/Features/Spark/SparkViewModel.swift:202-231,361-369
- Modify: NotieeTests/SparkViewModelTests.swift:6-25,87-303

**Consumes:** ChatMessage.citations, NoteRecord.isDeleted, and NoteRecord.isEncrypted.

**Produces:** The next ordinary-chat request receives only valid IDs cited by the assistant message immediately before the current user message.

- [ ] **Step 1: Extend MockAIService to record pin arguments**

In NotieeTests/SparkViewModelTests.swift, add beside askCallCount:

~~~swift
private(set) var receivedPinnedRecordIDs: [[UUID]] = []
~~~

Replace the mock ask body with:

~~~swift
func ask(
    question: String,
    recall: RecalledRecords,
    recentRounds: [ConversationRound],
    upcomingEvents: [ScheduledEvent],
    pinnedRecordIDs: [UUID]
) async throws -> (text: String, tokens: Int) {
    askCallCount += 1
    receivedPinnedRecordIDs.append(pinnedRecordIDs)
    return (responseText, responseTokens)
}
~~~

- [ ] **Step 2: Add failing ViewModel regression tests**

Add these helpers inside SparkViewModelTests:

~~~swift
private func makeRecord(
    title: String = "英文文章",
    detailedContent: String = "A complete English article."
) -> NoteRecord {
    NoteRecord(
        id: UUID(),
        capturedAt: Date(),
        localImagePaths: ["mock://article"],
        title: title,
        detailedContent: detailedContent
    )
}

private func waitForAskCount(
    _ expected: Int,
    service: MockAIService,
    timeoutIterations: Int = 100
) async throws {
    for _ in 0..<timeoutIterations {
        if service.askCallCount >= expected { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Expected \(expected) ask calls, got \(service.askCallCount)")
}
~~~

Add the natural-language regression:

~~~swift
func testImmediateNaturalFollowup_pinsPriorAssistantCitation() async throws {
    let mockAI = MockAIService()
    mockAI.responseText = "找到了这篇英文文章：[来源1]"
    let record = makeRecord()
    let vm = SparkViewModel(aiService: mockAI, repository: MockRepository())
    vm.recordsProvider = { [record] }

    vm.inputText = "有一篇英文拍记，帮我找出来"
    vm.sendMessage()
    try await waitForAskCount(1, service: mockAI)
    XCTAssertEqual(vm.messages.last?.citations.map(\.recordID), [record.id])

    vm.inputText = "对，就是这条"
    vm.sendMessage()
    try await waitForAskCount(2, service: mockAI)

    XCTAssertEqual(mockAI.receivedPinnedRecordIDs[0], [])
    XCTAssertEqual(mockAI.receivedPinnedRecordIDs[1], [record.id])
}
~~~

Add deletion and encryption filtering. Each starts with the same cited first turn, changes the provider data before the next turn, and asserts no pin:

~~~swift
func testImmediateFollowup_doesNotPinDeletedOrEncryptedRecord() async throws {
    for shouldEncrypt in [false, true] {
        let mockAI = MockAIService()
        mockAI.responseText = "找到了这篇英文文章：[来源1]"
        var currentRecords = [makeRecord()]
        let vm = SparkViewModel(aiService: mockAI, repository: MockRepository())
        vm.recordsProvider = { currentRecords }

        vm.inputText = "有一篇英文拍记，帮我找出来"
        vm.sendMessage()
        try await waitForAskCount(1, service: mockAI)

        if shouldEncrypt {
            currentRecords[0].isEncrypted = true
        } else {
            currentRecords[0].isDeleted = true
        }
        vm.inputText = "对，就是这条"
        vm.sendMessage()
        try await waitForAskCount(2, service: mockAI)

        XCTAssertEqual(mockAI.receivedPinnedRecordIDs[1], [])
    }
}
~~~

- [ ] **Step 3: Run the test and verify it fails before implementation**

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-spark-continuation-derived -only-testing:NotieeTests/SparkViewModelTests CODE_SIGNING_ALLOWED=NO
~~~

Expected: the natural-followup test fails. Current code inserts an empty assistant placeholder first and either reads its empty citations or rejects the confirmation through the keyword gate.

- [ ] **Step 4: Resolve citations before adding the placeholder**

In SparkViewModel.processQuestion, move allRecs and pin resolution before:

~~~swift
let aid = UUID()
messages.append(ChatMessage(id: aid, role: .assistant, content: ""))
~~~

Use:

~~~swift
let allRecs = recordsProvider?() ?? []
let previousAssistant = messages.dropLast().last(where: { $0.role == .assistant })
let pinnedRecordIDs = Self.computePinnedRecordIDs(
    previousAssistant: previousAssistant,
    allRecords: allRecs
)

let aid = UUID()
messages.append(ChatMessage(id: aid, role: .assistant, content: ""))
~~~

Delete the later duplicate allRecs declaration and old pin calculation. SendMessage has appended the current user message before processQuestion begins, so dropLast guarantees that the new turn cannot be selected.

Replace computePinnedRecordIDs with:

~~~swift
private static func computePinnedRecordIDs(
    previousAssistant: ChatMessage?,
    allRecords: [NoteRecord]
) -> [UUID] {
    guard let previousAssistant, !previousAssistant.citations.isEmpty else { return [] }
    let validIDs = Set(
        allRecords
            .filter { !$0.isDeleted && !$0.isEncrypted }
            .map(\.id)
    )
    return previousAssistant.citations.map(\.recordID).filter { validIDs.contains($0) }
}
~~~

Remove followupQuestion and the SparkIntentDetector.isShortFollowup gate from this path. Do not otherwise change SparkIntentDetector; it still serves Agent-mode action suggestions.

- [ ] **Step 5: Run focused ViewModel tests and verify they pass**

Run the Step 3 command.

Expected: TEST SUCCEEDED. The natural confirmation pins the cited record; records deleted or encrypted after the first reply do not.

- [ ] **Step 6: Commit only if authorized**

~~~bash
git add Notiee/Features/Spark/SparkViewModel.swift NotieeTests/SparkViewModelTests.swift
git commit -m "fix(spark): carry cited full text into next chat turn" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
~~~

### Task 2: Bound Full Text Across All Cited Records

**Files:**

- Modify: Notiee/Features/Spark/SparkAIService.swift:651-674
- Modify: NotieeTests/SparkPromptRecallTests.swift:35-73

**Consumes:** buildPinnedFullTextBlock(pinnedIDs:from:) and Task 1 citation IDs.

**Produces:** Pinned full text follows citation order and contains no more than 4,000 copied body characters across the entire block.

- [ ] **Step 1: Add failing aggregate-budget and ordering tests**

Add to SparkPromptRecallTests:

~~~swift
func testPinnedFullText_preservesPinnedIDOrder_andCapsTotalBodies() throws {
    let first = rec("第一篇", summary: "s1", body: String(repeating: "A", count: 3_000))
    let second = rec("第二篇", summary: "s2", body: String(repeating: "B", count: 3_000))

    let block = SparkAIService.buildPinnedFullTextBlock(
        pinnedIDs: [second.id, first.id],
        from: [first, second]
    )

    let secondRange = try! XCTUnwrap(block.range(of: String(repeating: "B", count: 100)))
    let firstRange = try! XCTUnwrap(block.range(of: String(repeating: "A", count: 100)))
    XCTAssertLessThan(secondRange.lowerBound, firstRange.lowerBound)
    XCTAssertEqual(block.filter { $0 == "B" }.count, 3_000)
    XCTAssertTrue(block.contains("…（内容过长已截断）"))

    let bodyCharacters = block.filter { $0 == "A" || $0 == "B" }.count
    XCTAssertEqual(bodyCharacters + "…（内容过长已截断）".count, 4_000)
}

func testPinnedFullText_allBlankBodies_returnsEmpty() {
    let first = rec("空一", summary: "s", body: "")
    let second = rec("空二", summary: "s", body: "   ")
    let block = SparkAIService.buildPinnedFullTextBlock(
        pinnedIDs: [first.id, second.id],
        from: [first, second]
    )
    XCTAssertEqual(block, "")
}
~~~

- [ ] **Step 2: Run prompt tests and verify they fail**

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-spark-continuation-derived -only-testing:NotieeTests/SparkPromptRecallTests CODE_SIGNING_ALLOWED=NO
~~~

Expected: old code filters records order rather than pin order and caps each record independently, so both new assertions fail.

- [ ] **Step 3: Implement citation-ordered aggregate truncation**

In SparkAIService, retain the existing budget constant and add:

~~~swift
private static let pinnedFullTextMaxChars = 4000
private static let pinnedFullTextTruncationSuffix = "…（内容过长已截断）"
~~~

Replace buildPinnedFullTextBlock with:

~~~swift
static func buildPinnedFullTextBlock(pinnedIDs: [UUID], from records: [NoteRecord]) -> String {
    guard !pinnedIDs.isEmpty else { return "" }

    let recordsByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
    var seenIDs = Set<UUID>()
    let pinned = pinnedIDs.compactMap { id -> NoteRecord? in
        guard seenIDs.insert(id).inserted else { return nil }
        return recordsByID[id]
    }
    guard !pinned.isEmpty else { return "" }

    var bodyBlock = ""
    var remainingCharacters = pinnedFullTextMaxChars
    for (index, record) in pinned.enumerated() {
        let body = record.detailedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, remainingCharacters > 0 else { continue }

        let includedBody: String
        if body.count <= remainingCharacters {
            includedBody = body
        } else {
            guard remainingCharacters > pinnedFullTextTruncationSuffix.count else { break }
            let prefixLength = remainingCharacters - pinnedFullTextTruncationSuffix.count
            includedBody = String(body.prefix(prefixLength)) + pinnedFullTextTruncationSuffix
        }

        let label = pinned.count > 1 ? "-- 拍记 \(index + 1): \(record.title) --\n" : ""
        bodyBlock += "\n" + label + includedBody + "\n"
        remainingCharacters -= includedBody.count
    }

    guard !bodyBlock.isEmpty else { return "" }
    return "## 完整内容（用户正在追问的拍记全文）\n" + bodyBlock
}
~~~

If fewer characters than the suffix remain, stop rather than exceed the aggregate budget. Headings and labels are not copied record-body characters and do not consume this 4,000-character limit.

- [ ] **Step 4: Run focused prompt tests and verify they pass**

Run the Step 2 command.

Expected: TEST SUCCEEDED. The tests prove pin-ID ordering, one aggregate cap, truncation notation, and blank-body behavior.

- [ ] **Step 5: Commit only if authorized**

~~~bash
git add Notiee/Features/Spark/SparkAIService.swift NotieeTests/SparkPromptRecallTests.swift
git commit -m "fix(spark): bound cited full-text continuation context" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
~~~

### Task 3: Verify Both Targets and Record the Handoff

**Files:**

- Modify: HANDOFF.md

**Consumes:** Tasks 1-2 passing tests.

**Produces:** Verified shared-target compatibility and a precise English relay entry.

- [ ] **Step 1: Run Spark regression coverage**

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-spark-continuation-derived -only-testing:NotieeTests/SparkViewModelTests -only-testing:NotieeTests/SparkPromptRecallTests CODE_SIGNING_ALLOWED=NO
~~~

Expected: TEST SUCCEEDED.

- [ ] **Step 2: Build the free target**

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-spark-continuation-derived CODE_SIGNING_ALLOWED=NO
~~~

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Build the BYOK target**

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project Notiee.xcodeproj -scheme Notiee+ -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-spark-continuation-derived CODE_SIGNING_ALLOWED=NO
~~~

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Add a verified English handoff entry**

At the top of HANDOFF.md, add the following with the real implementation date and actual command results:

~~~markdown
### YYYY-MM-DD — Spark citation full-text continuation fixed _(both targets)_

- Resolved cited record IDs from the immediately preceding assistant reply before appending the current placeholder; removed keyword gating from this path.
- Filtered deleted and encrypted records; selection uses Citation.recordID only.
- Full-text rendering now preserves citation order and uses one 4,000-character total body budget.
- SparkViewModelTests and SparkPromptRecallTests passed; both Notiee and Notiee+ builds succeeded.
~~~

Do not claim a test or build passed unless it was run.

- [ ] **Step 5: Commit only if authorized**

~~~bash
git add HANDOFF.md
git commit -m "docs: record Spark continuation verification" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
~~~

## Plan Self-Review

- **Spec coverage:** Task 1 fixes placeholder ordering, removes keyword dependence, and tests natural language plus deleted/encrypted filtering. Task 2 enforces citation order and the aggregate budget. Task 3 runs required tests/builds and records only verified evidence.
- **Scope:** No Agent, backend, UI, persistence, localization, or semantic-recall changes are included.
- **Type consistency:** SparkAIServing.ask is unchanged. computePinnedRecordIDs becomes a ChatMessage optional plus NoteRecord array to UUID array helper. buildPinnedFullTextBlock retains its static signature.
- **Placeholder scan:** Every edit, test, command, expected outcome, and authorized commit command is specified.
