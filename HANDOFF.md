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
