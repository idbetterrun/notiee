# Spark Fixes, Settings Reorg & Agent WebFetch — Design

Date: 2026-06-22
Branch: `feature/ai-agent`

## Overview

Seven independent work items against the Spark / Settings surface. Each is small
and self-contained; they share no state and can be implemented in any order.

| # | Item | Type |
|---|------|------|
| 1 | Spark title on the toolbar line (native bar) | UI fix |
| 2 | Local login returns to "我" page | Bug fix |
| 3 | Remove dead Agent toggle; reorganize AI settings | Refactor |
| 4 | Add "Spark" to App launch-page picker | Feature |
| 5 | Non-agent Spark can view schedule (read-only) | Feature |
| 6 | Lock thinking to "on" for `deepseek-v4-pro` | Bug fix |
| 7 | Agent `WebFetchTool` (URL fetch, agent-only) | Feature |

---

## 1. Spark title on the toolbar line

**Problem.** `SparkView.titleHeader` renders the conversation title as an
in-content header on its own line below the toolbar buttons
(`Notiee/Features/Spark/SparkView.swift:89`). The trailing toolbar buttons sit in
iOS's automatic liquid-glass capsule, so the detached title line looks ugly and
breaks the transparency at the top of the screen.

**Decision.** Native bar, no extra capsule. Move the title into the navigation
bar's **principal** toolbar slot so it shares the single system translucent bar
with the trailing buttons. No second glass pill → no "blob"; the top stays
see-through.

**Design.**
- Remove the `titleHeader` view and its use in `contentView`.
- Add a `ToolbarItem(placement: .principal)` containing an `HStack` with:
  the title `Text` (`.lineLimit(1)`, `.minimumScaleFactor(0.8)` to tolerate long
  titles), the existing `beta` badge (when `messages.isEmpty`), and the
  `isGeneratingTitle` `ProgressView`.
- Keep `navigationBarTitleDisplayMode(.inline)`.

**Acceptance.** Title and the ✏️/🕘 buttons render on one line in the system bar;
top of the chat content is transparent; long titles truncate/scale rather than
pushing a second row.

---

## 2. Local login returns to "我" page

**Problem.** Navigation chain is TodayView → `MeView` → `LoginView` →
`LocalLoginView`, all pushed via `NavigationLink`. `LocalLoginView`'s "完成"
button calls `account.localLogin(...)` then `dismiss()`, which pops only one
level — back to `LoginView` (the Notiee/TomaGo login screen), not to `MeView`.

**Design.** Drive the pop from login state, observing the shared
`AccountStore.live`:
- `LocalLoginView` keeps its `dismiss()` (pops itself → `LoginView`).
- `LoginView` adds `.onChange(of: account.isLoggedIn)` → when it flips to `true`,
  call its own `dismiss()`, popping back to `MeView`.

`MeView` already shows the profile section when `account.profile != nil`, so it
renders the logged-in "我" state immediately.

**Acceptance.** After "完成" on local login, the user lands on the "我" page
showing their profile, not the login screen.

---

## 3. Remove dead Agent toggle; reorganize AI settings

**Problem.** The Settings "Agent 模式" toggle (`spark_agent_enabled`) is never read
by Spark's runtime — `SparkViewModel.isAgentModeEnabled` is independent local
state defaulting to `false`, toggled only from the in-chat `SparkAgentChip`. The
settings toggle is a no-op ("摆设"). Meanwhile the AI section is a long flat list.

**Confirmed still in use** (must be preserved, migrated not deleted):
`spark_agent_trust_level`, `spark_agent_max_iterations`,
`spark_agent_max_tools_per_round` — consumed by `AgentTrustManager` /
`AgentExecutor`.

**Design.**
- Delete the entire "Agent 设置" `Section` and the `agentEnabled` toggle from
  `SettingsMainView`. Remove `agentEnabled` from `SettingsViewModel` (published
  property, init load, `saveAll` write) and stop writing `sparkAgentEnabled`.
  Leave the `UDK.sparkAgentEnabled` constant in place (harmless; avoids churn) but
  unreferenced — or remove it; implementer's choice during cleanup.
- New view **`SparkSettingsView`** (sub-page) with NavigationLinks to:
  - `SparkStyleSettingsView` (聊天风格)
  - `SparkMemoryView` (记忆)
  - new **`AgentSettingsView`** (Agent 设置): trust level picker, max-iterations
    stepper, max-tools-per-round stepper — moved verbatim from the old section,
    still bound to `SettingsViewModel` and persisted via `saveAll()`.
- Reorder the "大模型" section to:
  1. `启用大模型处理功能` (master toggle)
  2. `拍记完后立即分析`
  3. `文本模型 ›`
  4. `视觉模型 ›`
  5. `Spark ›` → `SparkSettingsView`
  6. `大模型功能 ›` → `AIFeatureSettingsView` (摘要/详细/待办)
  7. `测试双端连接` (+ status rows)
  8. `官方帮助文档 ›` (DisclosureGroup)
- `管理自定义模型` stays under "高级设置" (unchanged).

**Acceptance.** No Agent toggle anywhere in Settings; Agent trust/iteration/tool
params reachable via 大模型 → Spark → Agent 设置 and still take effect; AI section
matches the order above.

---

## 4. "Spark" launch-page option

**Problem.** The `App 启动页` picker hardcodes today/capture/records
(`SettingsMainView.swift:24`); `AppTab.spark` exists and `RootTabView` already has
a Spark tab, so launching into it works.

**Design.** Add `Text(AppTab.spark.titleKey).tag(AppTab.spark)` to the picker.
Optionally add `.spark` to `AppTab.launchCandidates` and drive the picker off that
array to keep it data-driven.

**Acceptance.** Selecting "Spark" as launch page opens the app on the Spark tab.

---

## 5. Non-agent Spark can view schedule (read-only)

**Problem.** Non-agent path (`SparkAIService.ask`) injects records + memory but no
calendar data; only Agent mode wires `CalendarQueryTool`. Per the nas/as
philosophy: non-agent Spark should **view** schedule but not **act** on it.

**Design.**
- Pass upcoming-schedule data into the non-agent prompt. `SparkViewModel` has
  `calendarManager`; build a compact block from `calendarManager.allEvents`:
  **next 7 days, capped at ~20 events**, sorted ascending, each line
  `MM-dd HH:mm 标题` (all-day events marked).
- Plumb it into `SparkAIService.ask` (add a `upcomingEvents:` parameter, or a
  pre-built `scheduleBlock` string — string keeps the service calendar-agnostic
  and is preferred). Inject under a new `## 近期日程 (未来7天)` section in
  `buildSystemPrompt`.
- **Honesty rules** (new prompt fragment) so it states limits instead of bluffing:
  - It can see only the next ~7 days; if asked beyond that window, say so and
    suggest narrowing the question.
  - It can **view** schedule but cannot create/modify it in this mode; for changes,
    tell the user to enable Agent 模式.
  - Never invent events not in the provided block.

**Acceptance.** With Agent mode off, asking "我这周有什么安排" yields the injected
events; asking to create/modify an event yields an honest "需要打开 Agent 模式";
asking about next month yields an honest "我只能看到未来一周".

---

## 6. Lock thinking to "on" for `deepseek-v4-pro`

**Problem.** `deepseek-v4-pro` (ds v4p) errors unless thinking is enabled. Current
DeepSeek mapping: off → `reasoning_effort:"minimal"`, on → `"high"`. Sending the
"off"/minimal path to this model fails.

**Design.** Introduce a small model-thinking policy:
- A helper (e.g. `ThinkingCapability.requiresThinking(provider:model:)` or a
  `ModelThinkingPolicy` type) returning, for `(deepseek, "deepseek-v4-pro")`, that
  thinking is **forced on**. Structured so more models can be added later.
- **UI** (`SparkView` thinking chip): when the effective model is locked, present
  only the forced level (e.g. just "开启思考") and make the chip non-interactive
  (or visibly locked). `thinkingTitle` reflects the forced level.
- **ViewModel** (`selectModel`): when switching to a locked model, set and persist
  `sparkThinkingLevelID` to the forced id ("on").
- **Service guard** (`SparkAIService.sparkModelAndExtraBody`): if the model is
  locked and the stored level is off/nil, apply the forced "on" level regardless —
  protects every call path (ask, title, memory, agent), not just the UI.

**Acceptance.** Selecting `deepseek-v4-pro` locks the thinking chip to "开启思考";
no request to it is ever sent with thinking off; switching back to another model
restores the full thinking options.

---

## 7. Agent `WebFetchTool` (URL fetch, agent-only)

**Decision.** URL fetch only (no open web search yet); **Agent mode only** (one
code path, fits existing tool architecture). Non-agent Spark gets no web access.

**Design.**
- New tool `Notiee/Features/Spark/Agent/Tools/WebFetchTool.swift` conforming to
  `AgentTool`:
  - `name = "web_fetch"`, `permission = .read`.
  - Param: `url` (string, required); optional `max_chars`.
  - `execute`: validate URL → fetch via `URLSession` → extract readable text from
    HTML → truncate → return as `AgentToolResult` (`success`, `message`, `data`).
  - Register in `SparkViewModel.makeAgentExecutor()` tool list.
- **Safeguards (required):**
  - **SSRF:** only `http`/`https`; reject hosts resolving to private/loopback/
    link-local ranges (10/8, 172.16/12, 192.168/16, 127/8, ::1, 169.254/16) and
    `localhost`; no redirects to such hosts.
  - **Prompt injection:** fetched text is wrapped and labeled as untrusted external
    DATA in the tool result; the agent prompt already instructs that tool output is
    data, not instructions. Reuse `containsInjectionPattern` awareness where
    practical, but the primary defense is the data/instruction boundary.
  - **Size/tokens:** cap response body (e.g. 1–2 MB download) and extracted text
    (e.g. ~8k chars) with truncation marker.
  - **Timeout:** request timeout (e.g. 10s); return a clear failure message on
    timeout/network error rather than throwing opaque errors.
- **HTML→text:** lightweight extraction (strip scripts/styles/tags, collapse
  whitespace). No new third-party dependency.
- **Privacy notice:** update `SparkPrivacySheet` copy to disclose that, in Agent
  mode, Spark may fetch web pages from URLs (data leaves the device to third-party
  sites).

**Acceptance.** In Agent mode, "总结一下 <url>" fetches and summarizes the page;
private/loopback URLs are refused; oversized pages are truncated; timeouts produce
a graceful message; non-agent mode has no web access; privacy sheet mentions web
fetch.

---

## Out of scope

- Open-ended web search (Brave/Bing/provider-native) — deferred; larger separate
  effort.
- Non-agent web access.
- Any change to how Agent mode itself is enabled (still the in-chat `SparkAgentChip`).

## Testing notes

- Unit-testable pure logic: schedule-block builder (date window + cap), thinking
  lock policy, WebFetch URL/SSRF validation and HTML→text extraction. Add tests
  under `NotieeTests` for these.
- UI/navigation items (1, 2, 4) verified manually in the running app.
