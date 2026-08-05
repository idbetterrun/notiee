# NewUIPreview Today / Records / Detail Implementation Plan

> Execute task-by-task with tests first. Do not commit or push unless the user explicitly requests it.

**Goal:** Implement the approved mock-only next-generation Today, Records masonry, and record-detail reading experience inside `NewUIPreview`.

**Architecture:** `NewUIPreviewState` owns stable fixtures, Today context selection, Records search, and overlay navigation. A custom `Layout` uses a pure geometry helper for true masonry. Detail remains a preview-local overlay so the source destination retains its state.

**Tech Stack:** SwiftUI, MarkdownUI, XCTest, iOS 18 deployment target with iOS 26 Liquid Glass APIs.

**Spec:** `docs/superpowers/specs/2026-08-05-new-ui-preview-today-records-detail-design.md`

## Global Constraints

- Classification: shared experimental UI for both Notiee and Notiee+.
- Scope is limited to `Notiee/Features/Settings/NewUIPreview/`, mock assets, preview tests, localizations, and project membership.
- Do not connect `NotieeStore`, mutate persistence, call backend/BYOK services, or modify production Today/Records/detail views.
- Add shared Swift files to both app targets and tests only to `NotieeTests`.
- Add visible strings to all three localization catalogs.
- Prefix Xcode commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Tasks

1. Add stable fixture/state types and state tests for Hero-to-section defaults, manual selection, search, protected data, and stable IDs.
2. Replace the old Today slots with an unframed Hero, module shortcuts, bounded Today selector, and non-intercepting capture gestures.
3. Add a true masonry Records destination, 0/1/2/3/4/5+ media templates, protected states, search, and geometry tests.
4. Add fixed-toolbar record detail with media pager, sticky selector, Markdown document, raw text/todos, search, scroll-to-top, and mock action sheets.
5. Integrate root routing and Liquid Glass accessibility fallbacks; register all files in both targets and localize copy.
6. Run focused and full tests, build both schemes, visually inspect accessibility/appearance variants, and update `HANDOFF.md`.

## Verification

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /private/tmp/notiee-new-ui-preview-tests \
  -only-testing:NotieeTests/NewUIPreviewStateTests \
  -only-testing:NotieeTests/NewUIPreviewMasonryLayoutTests \
  -only-testing:NotieeTests/NewUIPreviewRecordPresentationTests \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build -project Notiee.xcodeproj -scheme Notiee \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /private/tmp/notiee-new-ui-preview-free CODE_SIGNING_ALLOWED=NO

xcodebuild build -project Notiee.xcodeproj -scheme Notiee+ \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /private/tmp/notiee-new-ui-preview-plus CODE_SIGNING_ALLOWED=NO
```

Expected: focused tests pass, both schemes build, and manual iOS 26 QA confirms light/dark, Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, stable dock hit regions, masonry variants, sticky detail navigation, and unobscured final content.
