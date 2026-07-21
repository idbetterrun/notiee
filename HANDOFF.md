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
- **Backend is design-doc only in this repo.** `docs/backend/notiee-ai-proxy-design.md`
  describes it; there is **no backend implementation checked in here**. Client
  changes that depend on new backend behavior must be forward-compatible (degrade
  cleanly when the backend hasn't shipped the change yet).
- **Two targets, shared files:** always build BOTH `Notiee` and `Notiee+` when a
  shared file changes, to confirm `#if NOTIEE_PLUS` isolation holds.

---

## Work log

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
