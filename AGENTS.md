# AGENTS.md — Working Agreement

**Read this file at the start of every task. Then read `HANDOFF.md`.**

This project is an iOS app (Notiee) with a two-target setup. The rules below are
a standing agreement between the user and any agent working on this repo.

---

## 1. Startup ritual (every task, no exceptions)

1. Read `AGENTS.md` (this file).
2. Read `HANDOFF.md` — known pitfalls + what previous agents finished/left.
3. Do the work.
4. Before finishing: update `HANDOFF.md` with anything the next agent needs
   (pitfalls hit, things completed, follow-ups). Write it in **English**.
5. Report back to the user (see §4).

---

## 2. Two targets — always classify the change

The project ships **two apps from one codebase**:

| Target | Scheme | Product | Model | Flag |
|---|---|---|---|---|
| **Notiee** (free) | `Notiee` | `Notiee.app` | Free download + Pro subscription; AI paid via **self-hosted backend** (key on server) | `#if !NOTIEE_PLUS` |
| **Notiee+** (BYOK) | `Notiee+` | `NotieePlus.app` | One-time purchase; user brings own endpoint+key, calls model vendor directly | `#if NOTIEE_PLUS` |

**Isolation rules (from `docs/Notiee-免费版改造计划.md`):**
- Free-only new files → **only** added to the `Notiee` target (absent in Notiee+).
- Shared files that must compile in both but branch → use **`#if NOTIEE_PLUS`**.
- **Never** scatter ad-hoc `if isFreeVersion {}` runtime checks in shared files.
- Centralized `AppBranding` (`#if NOTIEE_PLUS`) is the established pattern — follow it.

**For every incoming instruction, the agent MUST decide and state:**
- Does this change affect **both targets**, **free only**, or **Plus only**?
- Classify it *before* coding, and repeat the classification in the final report.

Backend-dependent services (`AuthService`, `BackendAPIClient`, `EntitlementStore`,
`BackendAIProcessingService`, etc.) are **free-target only** — Notiee+ has no backend.

---

## 3. Build / verify

Xcode is installed at `/Applications/Xcode.app`, but `xcode-select` points at
CommandLineTools. Do **not** `sudo xcode-select -s`. Instead prefix commands:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project Notiee.xcodeproj -scheme Notiee \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath <scratchpad>/DerivedData \
  CODE_SIGNING_ALLOWED=NO
```

- When a change touches **shared files**, build **both** schemes (`Notiee` and
  `Notiee+`) to confirm the `#if` isolation holds.
- Available simulators include `iPhone 17`. First build is slow (SPM resolve).

---

## 4. Reporting back to the user

- Explain changes **in the chat in Chinese (中文)** every time there's a change.
- Always tell the user, per change, whether it hit **both targets / free only /
  Plus only**.
- Only commit/push when the user asks. If on `main`, branch first.
- Commit message trailer:
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## 5. Key facts about this repo

- SwiftUI + MVVM; central facade `NotieeStore` composing 4 managers via Combine.
- Persistence: local JSON stores + UserDefaults (settings) + **Keychain** (secrets).
  Keychain **survives app deletion**; UserDefaults does **not** — this asymmetry
  matters for "fresh install" detection (see `HANDOFF.md`).
- Localized strings live in `en.lproj` / `zh-Hans.lproj` / `zh-Hant.lproj`
  `Localizable.strings`. SwiftUI string literals are used **as localization keys**,
  so changing a UI literal means updating the matching key in all three files.
