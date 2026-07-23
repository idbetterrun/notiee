# HANDOFF.md — Agent-to-Agent Relay

**Read this before starting work. Update it before you finish.** English only.
This is the running log of pitfalls hit and work completed, so the next agent
doesn't re-learn the same lessons. Newest entries on top.

See `AGENTS.md` for the working agreement (startup ritual, two-target rules,
build commands, reporting rules).

---

## Pitfalls & gotchas (persistent — read every time)

- **Xcode vs CommandLineTools:** `xcode-select -p` points at CommandLineTools, so
  bare `xcodebuild` fails. Prefix every build with
  `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Do NOT run
  `sudo xcode-select -s` (don't mutate the user's global toolchain).
- **Keychain survives app deletion; UserDefaults does not.** A reinstalled app can
  read a stale `AuthService` session from the Keychain and look logged-in. Use a
  UserDefaults flag as the "fresh install" signal (see `UDK.hasBootstrappedInstall`).
- **SwiftUI literals are localization keys.** Changing a visible string literal
  (e.g. in `AboutNotieeView`) requires updating the matching key in all three
  `Localizable.strings` files (`en`, `zh-Hans`, `zh-Hant`), or the key/value drift.
- **Backend IS checked in — `notiee-ping-stream/`** (Express + Tencent SCF + MySQL,
  non-streaming). It implements Apple login→JWT, `/ai/chat`, `/ai/process` (vision+text,
  charges 1 "篇" quota), `/ai/agent` (tool relay), `/me/quota`, subscription verify, and
  App Store server notifications. `docs/backend/notiee-ai-proxy-design.md` is the *design*
  doc and is now partly behind the code (e.g. `/ai/agent` isn't in it yet). When in doubt,
  the running contract is `notiee-ping-stream/index.js`, not the design doc. Client changes
  that depend on *unshipped* backend behavior must still be forward-compatible (degrade
  cleanly — e.g. `NOT_IMPLEMENTED` → friendly fallback).
- **Two targets, shared files:** always build BOTH `Notiee` and `Notiee+` when a
  shared file changes, to confirm `#if NOTIEE_PLUS` isolation holds.

---

## Work log

### 2026-07-23 — Screenshot Shortcut + background processing plan ready _(both targets; planning only)_

- User-approved workflow: a user-authored Shortcut passes the output of iOS `Take Screenshot` to a new Notiee App Intent; it must save the image and create a record without foregrounding the app, then perform AI work in the background and send a terminal local notification.
- Formal spec: `docs/superpowers/specs/2026-07-23-screenshot-shortcut-background-processing-design.md`.
- Executable TDD plan: `docs/superpowers/plans/2026-07-23-screenshot-shortcut-background-processing.md`.
- The plan deliberately reuses persisted `NoteRecord` state as the durable queue rather than adding a second task database. It adds `BGProcessingTask` recovery for interrupted `.processing` work, but does not promise background timing or automatically retry a request that has already failed.
- Existing retry defect to fix during implementation: `NotieeStore.retryAIProcessing` currently changes `.failed` to `.pending` before calling `AIPipelineManager.retryAndEnqueue`, whose guard only accepts `.failed`/`.deadLetter`; the retry silently does not enqueue. Images and records already persist before the pipeline, and failures retain them.
- Do not start implementation, builds, commits, or a physical-device Shortcut test until the user explicitly requests execution. Preserve all existing worktree changes.

### 2026-07-23 — Spark citation full-text continuation fixed _(both targets)_

- Resolved cited record IDs from the immediately preceding assistant reply before appending the current placeholder; removed keyword gating from this path.
- Filtered deleted and encrypted records; selection uses Citation.recordID only.
- Full-text rendering now preserves citation order and uses one 4,000-character total body budget.
- **24 tests PASS** (SparkViewModelTests 15, SparkPromptRecallTests 9). Both Notiee and Notiee+ builds succeeded.
- Changes span `SparkViewModel.swift` (processQuestion reorder + new computePinnedRecordIDs), `SparkAIService.swift` (buildPinnedFullTextBlock rewritten for citation-order + aggregate budget), and their test files.

### 2026-07-23 — Product idea parked: fixed Today input canvas _(both targets; do not implement yet)_

- User direction: replace the four-tab navigation with custom three-part navigation (Today left, oversized Spark center, Records right) and remove Capture as a tab.
- Future Today should be a non-scrolling fixed home canvas. Pull down grows a camera circle; crossing about mid-screen fires one haptic and release opens rapid capture. Pull up mirrors this into an audio-recording entry. Audio is entry-only initially, without recording/transcription implementation.
- Important architecture decision: host vertical gesture state outside the replaceable Today content, not inside its current ScrollView. Do not retrofit the gesture into current scrolling Today; discuss/plan the near-term navigation work separately.

### 2026-07-23 — Task 2 of citation full-text continuation: bound full text across all cited records DONE _(both targets)_

- Replaced `buildPinnedFullTextBlock` in `SparkAIService.swift` with citation-ordered, aggregate-budget version.
- Old code: iterated `records` array order, capped each record independently at 4,000 chars.
- New code: iterates `pinnedIDs` order (citation order, dictionary lookup + dedup), shared 4,000-char budget, no per-record minimum guarantee.
- Added constant `pinnedFullTextTruncationSuffix = "…（内容过长已截断）"`.
- Labels/headings do NOT consume the 4,000-character budget.
- Added 2 new tests: `testPinnedFullText_preservesPinnedIDOrder_andCapsTotalBodies` (ordering + aggregate cap), `testPinnedFullText_allBlankBodies_returnsEmpty` (blank body edge case).
- All 9 SparkPromptRecallTests PASS. Not committed (waiting on user).

### 2026-07-23 — Task 1 of citation full-text continuation: resolve prior-citation IDs DONE _(both targets)_

- Fixed ordering bug: `computePinnedRecordIDs` now runs **before** the empty assistant placeholder is appended in `processQuestion`. Uses `messages.dropLast()` to skip the current turn's just-appended user message.
- Removed `SparkIntentDetector.isShortFollowup` gate from `computePinnedRecordIDs` — now accepts any immediate prior-assistant citation, not just keyword-triggered followups.
- New signature: `computePinnedRecordIDs(previousAssistant: ChatMessage?, allRecords: [NoteRecord]) -> [UUID]`.
- MockAIService gained `receivedPinnedRecordIDs: [[UUID]]` recording array.
- 2 new ViewModel integration tests: natural confirmation pins cited record; deleted/encrypted records filtered.
- All 15 SparkViewModelTests pass. Both Notiee + Notiee+ BUILD SUCCEEDED.
- **Pitfall:** `testImmediateFollowup_doesNotPinDeletedOrEncryptedRecord` passed even in red phase (the bug produced `[]` which matched expected `[]`). The fix's filter logic is correct — the test would have caught a regression.
- Not committed (waiting on user).

### 2026-07-23 — Citation full-text continuation implementation plan ready _(both targets; no source change)_

- Formal TDD plan: `docs/superpowers/plans/2026-07-23-spark-citation-fulltext-continuation.md`; companion spec: `docs/superpowers/specs/2026-07-23-spark-citation-fulltext-continuation-design.md`.
- The plan has three independently verifiable tasks: fix prior-citation resolution before placeholder insertion; make full-text injection citation-ordered with one aggregate 4,000-character budget; run Spark tests and build both schemes.
- User explicitly requested planning only. Do not begin implementation, build, commit, or push unless asked in a later task.

### 2026-07-23 — Citation full-text continuation spec ready _(both targets; no source change)_

- Approved design spec: `docs/superpowers/specs/2026-07-23-spark-citation-fulltext-continuation-design.md`.
- It replaces keyword-triggered pinning with one-turn, citation-scoped candidate context: on the next normal Spark message, inject valid cited records' full text and let the existing main model use conversation history to determine relevance. No extra LLM classifier, backend API, Agent behavior, or persistent selected-record state.
- Implementation must fix the placeholder-ordering bug, enforce a **total** 4,000-character pinned-content budget (not 4,000 per cited record), and add ViewModel integration coverage for a natural confirmation such as `对，就是这条`.

### 2026-07-23 — Diagnosed Spark plain-chat full-text follow-up failure _(both targets; no source change)_

- The 2026-07-22 short-followup pinned-full-text feature has a blocking ordering bug in `SparkViewModel.processQuestion`: it appends the current turn's empty assistant placeholder before calling `computePinnedRecordIDs`. That helper uses `messages.last(where: { $0.role == .assistant })`, so it always selects the new empty placeholder (no citations), not the preceding real assistant response. Result: `pinnedRecordIDs` is always empty and detailed content is never injected through this path.
- The reported confirmation text `对，就是这条` would also fail `SparkIntentDetector.isShortFollowup` even after the ordering bug is fixed, because the intentionally narrow pattern list has no confirmation/selection phrases. The intended test coverage currently tests the detector and the prompt block separately, but no ViewModel integration case catches the placeholder ordering issue.
- This is shared plain-chat code used by both Notiee and Notiee+; backend transport is not involved. For the first response, title-based citation fallback can still create a `Citation` when the model repeats the exact title, but the placeholder ordering still discards it at the next turn's pin calculation.

### 2026-07-23 — Read-only architecture orientation _(no product-target change)_

- Current branch is `feature/spark-semantic-recall`. The worktree already has user-owned, uncommitted changes in `AGENTS.md`, `README.md`, `docs/Notiee-Wiki.md`, and new Spark-recall design/plan documents. Preserve them; this orientation made no source changes.
- README is partly stale: it still calls Spark semantic/vector retrieval "planned" and describes the older lexical-only retrieval, but `SparkRecordRecall` + `SemanticSearchEngine` are implemented and wired. Trust current source and the 2026-07-21/22 work-log entries over that section of README.
- Free-backend planning doc also contains historical TODOs (notably Agent transport), while current backend/client handoff states `/ai/agent` has since been implemented locally. For API-contract work, inspect `notiee-ping-stream/index.js` as directed in the persistent gotchas.

### 2026-07-22 — Todo-extraction prompt fix + Spark pinned full-text injection _(both targets)_

**Two independent changes, both in shared files → both targets.**

**Change A: Todo extraction prompt semantic boundary** (`AIPromptProvider.swift`)
- Root cause: `todos` field prompt said "如果文本中包含任何需要执行的任务" — no subject boundary. News articles contain tasks (police investigate, committee follows up) but executor is a third party, not the user.
- Fix: All 3 language branches (EN, zh-Hant, zh-Hans) now require: (a) executor must be the user personally; (b) informational content (news, articles, reports) → `todos = []`. Few-shot anti-pattern baked into the new wording.
- Pure prompt-text change, no logic or interface impact.

**Change B: Short-followup pinned full-text injection** (`SparkAIService`, `BackendSparkAIService`, `SparkViewModel`, `SparkIntentDetector`)
- Root cause: Anchor-layer records only get title + 100-char summary in system prompt; `detailedContent` is never sent. When user follows up with "翻译一下" on a cited article, Spark has no body to translate.
- Trigger conditions (all 3 must hold):
  1. User message < 15 chars AND matches followup patterns (翻译/展开/详细/继续/...), detected by `SparkIntentDetector.isShortFollowup()`
  2. Last assistant message has non-empty `citations` (from `[来源N]` → `Citation.recordID`)
  3. Cited record still exists + not deleted/encrypted
- Injection: `buildSystemPrompt` gains `pinnedRecordIDs: [UUID]` param (default `[]` for backward compat). When non-empty, `buildPinnedFullTextBlock` appends a `## 完整内容` section with `detailedContent` (capped at 4000 chars).
- Protocol `SparkAIServing.ask` signature changed: added `pinnedRecordIDs: [UUID]`.
- `BackendSparkAIService.ask` passes through to shared `buildSystemPrompt`.
- `SparkViewModel.computePinnedRecordIDs()` assembles pinned IDs from last assistant's citations.

**Design notes for future agents:**
- `[来源N]` → `Citation.recordID` is the **reliable signal** for "which record was just cited" — do NOT attempt title-matching (titles get paraphrased).
- This is heuristic-based (short + pattern), not semantic. False negatives OK (just won't inject full text); false positives cost unnecessary tokens. Current patterns are intentionally narrow.
- Only covers last-turn citations (not multi-turn). Future: could extend by walking citations further back in `messages`.

**Tests added:**
- `SparkIntentDetectorTests`: 3 new tests (short followup detected, not detected on normal questions, not detected on long messages). 7 total.
- `SparkPromptRecallTests`: 5 new tests (pinned full text injection, empty IDs, record-not-found, multiple records, empty body skip). 7 total.
- All 29 Spark-related tests (SparkViewModel 13, SparkRecordRecall 4, SparkPromptRecall 7, SparkIntentDetector 7) **PASS**.
- Both `Notiee` + `Notiee+` schemes **BUILD SUCCEEDED**.

**Pitfalls hit during implementation:**
- `\bmore\b` regex with NSRegularExpression requires doubled backslashes in Swift string literals.
- Single-word patterns like "这个" are too broad as followup signals — caused false positives on normal questions. Replaced with more specific compound patterns.
- Initial `buildPinnedFullTextBlock` returned the header even when all pinned records had empty `detailedContent`. Fixed by building bodyBlock first, then guarding on `!bodyBlock.isEmpty` before adding header.

### 2026-07-21 (13) — Semantic-recall: ALL 7 TASKS COMPLETE, branch approved for merge _(both targets)_

- Subagent-driven development completed. 6 commits, 7 tasks. Each task independently reviewed.
- **28 tests PASS** (SparkRecordRecall 4, SparkPromptRecall 2, SparkViewModel 13, SemanticSearchEngine + CitationStrip 9). **Both Notiee + Notiee+ BUILD SUCCEEDED.**
- **Final branch review: APPROVED — ready to merge to main.**
- Key correctness verified: citation mapping (record.id not position), encrypted record privacy, dedup, cap enforcement.
- Arch note: `makeAgentExecutor()` creates second engine instance — both share `EmbeddingIndex.live` on disk, vectors shared; architecturally not ideal but safe in practice.
- Branch: `feature/spark-semantic-recall`. Merge: `git checkout main && git merge --ff-only feature/spark-semantic-recall`.

### 2026-07-21 (12) — Task 6 of Spark semantic recall: cold-start semantic index backfill (DONE)

- Added `backfill(records:)` to `SemanticSearching` protocol in NoteSearchTool.swift.
- `SemanticSearchEngine` already had `backfill` — protocol conformance auto-satisfied.
- Added `warmUpSemanticIndex()` to `SparkViewModel` with `didWarmUpSemantic` guard (one-shot).
- `SparkView.onAppear` triggers warmup: `Task { await viewModel.warmUpSemanticIndex() }`.
- Uses `recordRecall.engine.backfill` (protocol type) — not `semanticEngine?` which is `nil` with stubs.
- Fixed `StubEngine` in NoteSearchToolTests to add `backfill` stub (protocol conformance error).
- Added `StubSearch.backfillCount` + `testWarmUp_backfillsOnce` — verifies backfill fires exactly once.
- Both schemes BUILD SUCCEEDED. All 4 SparkRecordRecallTests PASS.
- Committed on `feature/spark-semantic-recall` as `2e498a1`.
- **Spark semantic recall plan: all 7 tasks COMPLETE.**
- **Pitfall:** `semanticEngine` property is typed as `SemanticSearchEngine?` (concrete), but the `searchEngine` init param is `SemanticSearching` (protocol). When a stub is passed, `engine as? SemanticSearchEngine` returns `nil` → `semanticEngine?.backfill()` silently no-ops. Fix: use `recordRecall.engine.backfill()` which delegates through the protocol.

### 2026-07-21 (11) — Task 5 of Spark semantic recall: ViewModel wiring + citation fix (DONE)

- Injected `SparkRecordRecall` and `SemanticSearchEngine?` into `SparkViewModel.init` via new `searchEngine`/`anchorCount` params.
- `processQuestion` now calls `recordRecall.recall(query:from:)` on `@MainActor` before the detached `ask()` task, passing the real `RecalledRecords` (not the flat wrapper).
- Citation mapping now uses `recall.records` — fixes the position-based bug where a semantically-jumped-in old record would get the wrong `[来源N]` index.
- Extracted `SparkAIService.mapCitations(from:records:) -> [Citation]` as a `nonisolated static` pure function; instance `extractCitations`/`extractCitationsFallback` now delegate to static helpers.
- New test `testCitation_mapsToRecalledRecord_notFullListPosition` verifies: 3 records, anchorCount=1, `[来源2]` maps to oldHit not mid.
- Both schemes BUILD SUCCEEDED. All 13 SparkViewModelTests PASS.
- Committed on `feature/spark-semantic-recall` as `8f57920`.
- **Next (Task 6):** Warm-up backfill — call `semanticEngine?.backfill(records:)` at app start.

### 2026-07-21 (10) — Task 4 of Spark semantic recall: ask(recall:) protocol change (DONE)

- Changed protocol `SparkAIServing.ask` signature: `with allRecords: [NoteRecord]` → `recall: RecalledRecords`.
- `SparkAIService.ask`: removed flat-array filter/sort/prefix computation (7 lines); uses `recall` parameter directly.
- `BackendSparkAIService.ask`: removed flat-array computation (5 lines); uses `recall` parameter directly.
- Deleted `static let maxRecordsInPrompt = 150`.
- Updated `MockAIService.ask` signature in `SparkViewModelTests.swift`.
- Updated `SparkViewModel.sendMessage()` call site with temporary `RecalledRecords(records: semanticStartIndex:)` wrapper (Task 5 will replace with real recall pipeline).
- **Pitfall:** pbxproj had duplicate build file ID `1803E40E` for both `SparkRecordRecall.swift` and `SparkPromptFragments.swift` in Notiee+ target, causing "Skipping duplicate build file" and `RecalledRecords` not in scope. Added unique ID `1803E429` for SparkRecordRecall. This was a pre-existing corruption from Task 1.
- Both schemes (`Notiee` + `Notiee+`) BUILD SUCCEEDED. All 12 SparkViewModelTests pass.
- Committed on `feature/spark-semantic-recall` as `027a8e5`.
- **Next (Task 5):** ViewModel wiring — replace temporary `RecalledRecords(records: semanticStartIndex: recs.count)` in `sendMessage()` with real recall from `SparkRecordRecall.recall(query:from:)`.

### 2026-07-21 (9) — Task 3 of Spark semantic recall: layered record block render (DONE)

- Changed `buildSystemPrompt` signature from `records: [NoteRecord]` to `recall: RecalledRecords`.
- Record block now renders two layers: anchor (title+100char summary, continuous from [记录1]) and semantic (full text via `recordFullText`, 800char truncated, numbered after anchors).
- Added `static func recordFullText(_ r: NoteRecord) -> String` — joins title/summary/detailedContent/ocrText, same sourcing as vector embedding for hit consistency.
- Template count changed from `records.count` to `all.count`.
- Updated `SparkAIService.ask` and `BackendSparkAIService.ask` callers to wrap existing `activeRecords` array in `RecalledRecords(records:semanticStartIndex: records.count)` (all treated as anchors, no semantic layer yet — Task 4 will replace with real recall).
- Created `NotieeTests/SparkPromptRecallTests.swift` — 2 tests: layered rendering with continuous numbering, empty recall safety. Both pass.
- Added test file to pbxproj (BuildFile, FileReference, group, Sources build phase — 4 entries). Notiee scheme BUILD + TEST SUCCEEDED.
- Committed on `feature/spark-semantic-recall` as `6f83cc1`.
- **⚠️ For Task 4:** The `semanticStartIndex: recentRecords.count` placeholder in `ask()` callers means semantic layer is empty. Task 4 should replace with real `recall` from `SparkRecordRecall`.


- Added `recall(query:from:) async -> RecalledRecords` to `SparkRecordRecall` — filters deleted/encrypted, sorts anchors by recency, delegates semantic search to engine, calls merge.
- Added `SemanticSearchEngine.liveForSpark(settingsStore:)` static factory — encapsulates cloud/hybrid embedding assembly, DRY'd from `SparkViewModel.makeAgentExecutor()`.
- `SparkViewModel.makeAgentExecutor()`: 5 lines of manual engine assembly replaced with single `SemanticSearchEngine.liveForSpark(settingsStore:)` call.
- Added `StubSearch` stub engine + `testRecall_mergesAnchorsAndSemantic_excludesEncryptedFromCandidates` async test (3 tests total, all pass).
- Both schemes (`Notiee` + `Notiee+`) BUILD SUCCEEDED.
- Committed on `feature/spark-semantic-recall` as `166d81c`.
- **Pitfall:** Edit tool replaced `private func ensureVector` prefix without keeping the remainder of the signature, causing `}(for record: NoteRecord) async -> [Float]? {` — fixed by replacing the fused line with proper closing `}` + full method signature.

### 2026-07-21 (7) — Task 1 of Spark semantic recall: RecalledRecords + merge (DONE)

- Created `Notiee/Features/Spark/SparkRecordRecall.swift` — `RecalledRecords` value type + `SparkRecordRecall` struct with `merge(anchors:semantic:cap:) -> RecalledRecords` static pure function.
- Created `NotieeTests/SparkRecordRecallTests.swift` — 2 tests: duplicate exclusion + boundary reporting, cap truncation + boundary clamping. Both pass.
- Added both files manually to `project.pbxproj` for both Notiee and Notiee+ targets, plus test target. Both schemes BUILD SUCCEEDED.
- Committed on `feature/spark-semantic-recall` as `8db0b9e`.
- **Pitfall:** `PBXFileSystemSynchronizedRootGroup` only applies to `NotieeWidget` — main app and tests still require manual pbxproj entries. Budget ~72 lines of pbxproj per new shared file.
- `merge` is `@MainActor` (struct-level annotation) but operates on pure data; nonisolated refactor is safe but low priority.

### 2026-07-21 (6) — Semantic-recall IMPLEMENTATION PLAN ready to hand off

- Motivation confirmed by user: plain chat's newest-150 dump means records past
  150 are invisible + ~10k tokens/turn (metered-backend cost blowup).
- **Executable plan written** (writing-plans skill, TDD, 7 tasks):
  `docs/superpowers/plans/2026-07-21-spark-semantic-recall.md`. Spec/background:
  `docs/Spark语义召回改造方案.md`.
- Approach: layered hybrid (anchor top-15 title+summary + semantic top-K full
  text), merged into one ordered `RecalledRecords`; recall runs in the @MainActor
  ViewModel (engine is @MainActor), `ask()` stays off-main and pure.
- **Handoff:** user will assign this to someone else. Plan assumes zero context —
  exact paths, real code, per-task commit + `iPhone 17` build/test commands.
  Start on branch `feature/spark-semantic-recall`; both schemes must stay green.
- **Highest-risk task = Task 5** (`[来源N]` citation remap by `record.id`, not
  list position). Has a dedicated correctness test. Do not skip it.
- Engine already exists and is used by Agent `note_search` + detail "related notes";
  this plan just wires it into plain chat and DRYs the assembly into
  `SemanticSearchEngine.liveForSpark(settingsStore:)`.
- NOT started — plan only. No source changed by this step (see (5) for the bug fix
  that WAS applied and built).

### 2026-07-21 (5) — Agent timeline leaked into plain chat + semantic-recall plan

**Bug fix — stale Agent timeline in plain chat** _(both targets)_
- Symptom: after running one Agent task, turning Agent mode OFF and sending a
  plain message still popped the tool-call timeline (same tools as the prior
  Agent run), which vanished once the reply arrived.
- Root cause: timeline shows when `state == .loading && (currentToolName != nil
  || !agentActions.isEmpty)`. `sendOrRun()` (Agent path) clears `agentActions`,
  but `sendMessage()` (plain path) did not — so the previous run's actions
  lingered during the plain reply.
- Fix (`SparkViewModel.sendMessage`): clear `agentActions = []` and
  `currentToolName = nil` when starting a plain reply. Free scheme BUILD SUCCEEDED.

**Plan (NOT implemented) — Spark plain-chat semantic recall**
- Wrote `docs/Spark语义召回改造方案.md`. Motivation (from user): current plain
  chat dumps the newest 150 records every turn → (a) records past 150 are invisible
  forever, (b) ~10k tokens/turn = cost blowup on the metered free backend.
- Recommendation: **layered hybrid**, NOT full switch to semantic. Anchor layer
  (top ~15 recent, title+summary) preserves browse/timeline queries; semantic
  layer (top-K, full text via existing `SemanticSearchEngine`) breaks the 150 cap
  and deepens answers. Net tokens DROP (~3k vs ~10k).
- Engine already exists (`Services/Semantic/`, wired into Agent `note_search` +
  detail "related notes"); plain chat just never used it. Changes are in shared
  `SparkAIService.ask`/`buildSystemPrompt` (both targets); embedding source is the
  only fork (BYOK cloud vs free local `NLEmbedding`), absorbed by
  `HybridEmbeddingService.preferCloud` — no `#if` needed.
- **⚠️ Highest-risk part when implementing: `[来源N]` citation mapping.** Today it
  relies on records being a prefix of the full sorted array (position-based). A
  hybrid merged list (with jumped-in old records) breaks that — must remap
  citations by explicit `record.id`, not position. See plan §4.3.
- Free-tier cloud embeddings deferred: local `NLEmbedding` first (anchor layer is
  the safety net), open backend `/ai/embed` later as a smooth upgrade.

### 2026-07-21 (4) — Backend `/ai/agent` route implemented + 404 fallback _(free + backend)_

- Symptom after (3): error became "服务器错误 404". Backend log showed Express
  default HTML `Cannot POST /ai/agent` — the route simply didn't exist.
- **Backend now lives locally at repo-root `notiee-ping-stream/`** (single-file
  Express `index.js`, Tencent SCF deploy target). It's **gitignored** (already in
  `.gitignore` line 22) — NOT part of the iOS repo, deployed separately.
  - Run locally: `ALLOW_FAKE_APPLE=1 PORT=9000 node index.js` (in-memory store,
    no DB). Client DEBUG points at `http://127.0.0.1:9000`.
  - Fake login for testing: `POST /auth/apple {"identityToken":"fake-xxx"}` → JWT.
- Implemented `POST /ai/agent` in `index.js` (mirrors `/ai/chat`): tier-gated to
  **Pro only**, validates model, calls new `callUpstreamAgent(...)` which passes
  OpenAI `tools` through for openai-format providers (deepseek/doubao) and
  **translates OpenAI⇄Anthropic** for minimax (`openaiMessagesToAnthropic`).
  Returns `{ text, tokensUsed, toolCalls }`. Tools EXECUTE on-device; backend only
  relays the model call.
- Verified locally: route exists (no more 404); free user → `403 UPGRADE_REQUIRED`;
  unknown model → `400 BAD_MODEL`; empty messages → `400 BAD_REQUEST`; no token →
  `401`. Translation fn unit-tested (system hoist, tool_use / tool_result blocks).
- Client (`BackendSparkAIService.agentChat`): the `catch` now also treats a bare
  **HTTP 404** (Express HTML default) as "coming soon", not just structured
  `NOT_IMPLEMENTED` — so a not-yet-deployed backend degrades gracefully.
- Doc: added §6.3 `/ai/agent` contract to `docs/backend/notiee-ai-proxy-design.md`.
- **⚠️ Still TODO on backend before this works in prod:** deploy the updated
  `index.js` to SCF, and set a real Pro user (via `/subscription/verify`) — a
  genuinely Pro account is required for Agent to pass the tier gate. Also the
  in-memory store resets on cold start; production needs the MySQL store (DB_HOST).

### 2026-07-21 (3) — Spark Agent execution failed on free version _(free only)_

- Symptom: Pro user, Agent toggle ON, but running a task showed "Agent 执行出错：
  AI 调用失败：Agent 模式暂不支持，敬请期待". This is a SECOND gate, separate from
  the UI toggle fixed in (2).
- Root cause: `BackendSparkAIService.agentChat` (free version's backend-routed
  Spark) was a hardcoded stub that always `throw`s — regardless of tier. Only the
  BYOK `SparkAIService.agentChat` had a real implementation.
- Fix (`BackendSparkAIService.swift`): implemented `agentChat` to POST
  `messages` + OpenAI `tools` to backend `POST /ai/agent`, parse `text` +
  `toolCalls` (reuses the same dual OpenAI/Anthropic tool-call parsing as BYOK).
  Tool *execution* stays on-device in `AgentExecutor`; backend only relays the
  model call. If backend replies `NOT_IMPLEMENTED`, we fall back to the friendly
  "coming soon" message (forward-compatible).
- **⚠️ Backend TODO (not in this repo):** implement `POST /ai/agent` — accept
  `{model, messages, tools}`, forward to the text model with tool-calling, return
  `{text, tokensUsed, toolCalls:[...]}` (OpenAI or Anthropic tool-call shape).
  Until then Agent on free still shows "coming soon" but no longer a raw error.
  NOTE: `/ai/agent` is NOT documented in `docs/backend/notiee-ai-proxy-design.md`
  (§6 only has `/ai/chat` without a tools field) — the contract needs adding.

### 2026-07-21 (2) — Camera hang, Spark Agent gating, SOUL.md style import

_All shared files; verified both `Notiee` and `Notiee+` BUILD SUCCEEDED._

**Task 1 — camera slow to start / occasional hang** _(both targets)_
- `CameraManager.swift`: added `isConfigured` guard (session-queue only). Second
  `configureSession()` pass previously re-added inputs/outputs to a live session
  → deadlock. Now: configure once; a repeat call just (re)starts. Also
  `startRunning()` now fires directly on the session queue after commit instead of
  hopping to `@MainActor` first (that hop delayed the first frame → felt slow).

**Task 2 — free-version Pro user couldn't use Spark Agent** _(free only)_
- Root cause: `SparkTierLimits.isAgentAllowed` reads `CurrentEntitlement.tier`,
  which is only written by `EntitlementStore.refresh()` — and refresh only ran
  from `QuotaCard` (Me tab) or a purchase. A Pro user who cold-launched into Spark
  without visiting Me was still `.free` → Agent locked.
- `RootTabView.swift` `onAppear` (`#if !NOTIEE_PLUS`): `Task { await
  EntitlementStore.shared.refresh() }` on cold launch.
- `SparkView.swift` (`#if !NOTIEE_PLUS`): `@ObservedObject EntitlementStore.shared`
  so the Agent chip re-renders/unlocks once the refresh resolves Pro.

**Task 3 — Spark chat-style "+" → two-level menu** _(both targets)_
- `SparkStyleSettingsView.swift`: the toolbar `+` is now a `Menu` with
  「新建经典风格」(existing `AddCustomStyleSheet`) and「通过 SOUL.md 导入 beta」.
- New `SoulImportSheet`: `fileImporter` for a `.md` file → content becomes the
  style instruction, title = first `# H1` or the filename. Below the upload entry
  is a 规范参考 (spec reference) block. Reuses `addCustomStyle(...)`, so SOUL styles
  land in the same custom-styles list. `import UniformTypeIdentifiers` added.

### 2026-07-21 — Three fixes (verified: both targets BUILD SUCCEEDED)

**Fix 1 — ICP filing number** _(both targets; free-facing but shared file)_
- `AboutNotieeView.swift:87`: placeholder → `湘ICP备2026027627号-1`.
- Updated matching key in all three `Localizable.strings` (line 378). zh-Hant uses
  「備案號」; en keeps the Chinese filing string verbatim (MIIT requirement).

**Fix 2 — reinstalled app showed Pro quota before login** _(free only)_
- Root cause: Keychain `AuthService` session survives deletion → treated as
  logged-in → `QuotaCard` fetches old account's quota.
- `UserDefaultsKeys.swift`: added `hasBootstrappedInstall`.
- `AuthService.swift`: added `purgeStaleSessionOnFreshInstall(defaults:)` — first
  launch with no flag → set flag + `signOut()` (clears Keychain). No-op afterward.
- `NotieeApp.swift` `AppDelegate` (`#if !NOTIEE_PLUS`): call it before dev-login.

**Fix 3 — Apple login name always "Apple 用户"; chose Plan A (backend stores name)**
_(free only)_
- Root cause: Apple returns `fullName` only on the FIRST authorization per Apple ID;
  reinstall → `nil`. The identity token itself carries no name. (Avatar is never
  provided by Sign in with Apple — still user-uploaded, out of scope.)
- `AuthService.swift`: `BackendSession` gained `name`; `appleLogin(...)` gained a
  `name` param that is POSTed to `/auth/apple`; `persistSession` parses returned `name`.
- `LoginView.swift:270`: prefer `session.name` (backend's stored name) over the
  local Apple `name`, so reinstalls recover the first-login name.
- **Forward-compatible:** backend not returning `name` → `session.name == nil` →
  falls back to prior behavior, no regression.

**⚠️ Backend TODO (not in this repo — do on the backend side):**
- `POST /auth/apple`: accept optional `name`; persist it **only on the Apple
  userId's first login** (never overwrite on later logins — avoid tampering).
- `POST /auth/apple` response: echo back the stored `name`.

**Status:** Uncommitted working-tree changes on `main`. 8 files modified. Both
`Notiee` and `Notiee+` schemes build clean. Not yet committed (waiting on user).
