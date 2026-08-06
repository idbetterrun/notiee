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

### 2026-08-06 — Packaged the updated free backend for root-level extraction _(free target only)_

- Created `notiee-ping-stream-notti-memory-2026-08-06.zip` at the repository root without overwriting the older `notiee-ping-stream.zip`. The archive contains the backend directory's contents at ZIP root, including `node_modules`, certificates, source, tests, lockfile, schema, and SCF bootstrap; `.DS_Store` is excluded.
- `unzip -t` reports no errors. The archive contains 2,076 entries, has no `notiee-ping-stream/` path prefix, is 3.6 MB compressed, and has SHA-256 `f92d21f7f2d303e51eb74ba6a2289182f4526c2612a46806febe6011e30a5ab2`.

### 2026-08-06 — Completed the Notti memory refactor and closeout hardening _(both targets; free-only backend extractor)_

- Replaced current Spark product/source naming with Notti while preserving the legacy `spark` storage identifiers, files, exact placeholder-title migration, settings keys, record source encoding, and generated-folder UUIDs needed for upgrade and rollback compatibility. The shared iOS implementation now has one encrypted local memory domain, hybrid bounded recall, independent evidence/access reinforcement, lifecycle states, a durable extraction queue, strict local proposal resolution, sensitive confirmation, management UI, and confirmed destructive Agent deletion.
- Added repository-wide in-memory rollback boundaries for snapshot and vector persistence failures. Queue changes, proposal resolution, pending decisions, lifecycle transitions, status changes, touches, and vector replacement now restore the snapshot, vectors, and rebuild flag when atomic persistence throws; the existing two-file delete/edit compensation remains in place.
- Accepted sensitive proposals now remove only pending items whose normalized proposal text matches after the user explicitly asks Notti to remember the fact or confirms it. Focused tests cover this flow plus representative snapshot and vector persistence rollback, alongside migration, retrieval, secret rejection, Agent deletion, and compatibility coverage.
- Corrected every bundled and website privacy-policy mirror that claimed Keychain data is automatically removed on uninstall or that uninstall clears all local data. The policies now disclose that Keychain items may survive uninstall and direct users to in-app delete/reset/clear controls before uninstalling when complete removal is required.
- Verification completed without Simulator/XCTest per user direction: all Notti Swift sources and the focused test file pass Swift parsing; backend syntax passes; all 23 Node tests pass; pbxproj and all three localization files pass plist lint; legal false-claim scans and `git diff --check` are clean. Remaining `Spark` occurrences in current source/tests are migration compatibility values, fixtures, historical text, or the `sparkles` SF Symbol.
- Physical-device XCTest/build and UI migration validation remain with the user's device workflow. The free backend source is implemented but `/ai/memory/extract` has not been deployed to production. No commit or push was created; work remains directly on `main` as required by `AGENTS.md`.

### 2026-08-06 — Verified Mem0 decay, access reinforcement, and count-based ranking claims _(both targets; architecture investigation only)_

- The claim is accurate only when scoped to Mem0 Platform v3 and split into separate mechanisms. Platform Memory Decay is opt-in, records a fire-and-forget touch for every returned search result, retains the latest 20 access timestamps, and applies a bounded `0.3x...1.5x` search-time multiplier after relevance/reranking. It is soft reordering, not eviction, and is explicitly unavailable in the OSS SDK.
- Repeated user mentions do not increment a visible mention counter in the OSS v3 pipeline. Exact repeats are hash-deduplicated, the extraction prompt suppresses semantic duplicates, and Platform Dream handles repetition through Merge or scheduled Synthesis rather than a direct mention-frequency score.
- OSS entity retrieval does contain a memory-count term, but it penalizes broad entities: `1 / (1 + 0.001 * (linkedCount - 1)^2)` reduces each entity boost as that entity links to more memories. It should not be described as repeated mentions strengthening a fact. Base OSS ranking fuses semantic similarity, normalized BM25, and this entity boost; an optional reranker is separate.
- Mem0 lifecycle controls are distinct: decay only reorders; expiration hides by default but retains data; Dream Supersede marks old facts yet leaves them visible unless `latest_only`; Dream Merge hides retained duplicates by default; explicit delete is destructive. Feedback is a separate Platform API whose exact scoring effect is not exposed in this checkout.
- For Spark, keep evidence repetition and retrieval usage as separate metadata/signals. Access reinforcement should be bounded and category-aware, should apply only to memories actually injected/used rather than the broad candidate pool, and must never silently delete durable profile/safety facts. No product code changed; only this handoff note was added.

### 2026-08-06 — Assessed `mem0-main` as the reference for a Spark memory redesign _(both targets; architecture investigation only)_

- The useful Mem0 boundary is a standalone memory layer with separate post-response extraction and pre-response retrieval. Its v3 write path uses one ADD-only structured extraction call, semantic context lookup, exact-hash deduplication, embeddings, metadata/history, and optional entity links; retrieval fuses semantic, normalized BM25, and entity signals before returning only relevant memories.
- Spark currently has three overlapping write paths: hidden CRUD tags in the main answer, a personal-info-triggered background extraction, and 10-round compression. The two background paths write `SparkMemoryStore` directly and bypass `SparkTierLimits`, while the read path injects the complete `[String: String]` dictionary into every prompt. The current model has no stable memory ID, timestamps, provenance, temporal status, history, embedding, relevance score, or tests dedicated to memory persistence/retrieval.
- Recommended direction is a shared, local, Mem0-inspired Swift memory domain for both targets, reusing Notiee's existing embedding primitives and keeping transport behind a protocol. Do not embed the Python/TypeScript SDK or require Mem0 Cloud. Free-only backend extraction may branch at the transport boundary; Notiee+ remains BYOK. Migration from `spark_memory.json` must be explicit and idempotent.
- Do not assume the checked-in OSS code implements all advertised v3 behavior: Mem0's temporal reasoning, decay, graph memory, and published benchmark optimizations are managed-platform features; OSS rejects `timestamp`/`reference_date`, and the README explicitly says benchmark results include proprietary optimizations.
- No Swift, backend, project, localization, persistence data, or target membership changed. Only this handoff note was added; no build or test was needed.

### 2026-08-06 — Audited prior Spark memory-system discussion history _(both targets; investigation only)_

- The accessible recent Codex task history contains no dedicated conversation explicitly about a "Spark memory system refactor." Repository history does contain the original Spark v3 memory-mechanism plan (`docs/superpowers/plans/2026-06-03-spark-v3-personality-streaming.md`), the later free-tier memory-cap plan, and semantic record-recall work; these are related but should not be conflated with a newly proposed long-term-memory redesign.
- No Swift, project, localization, persistence, backend, or target-membership file changed. Only this handoff audit note was added; no build or test was needed.

### 2026-08-05 — Made NewUIPreview Today height-adaptive and restored an opaque detail layer _(both targets; experimental preview only)_

- Today now measures the rendered Hero and `Today + selector` header, reserves the 44 pt contextual action and 104 pt Dock/capture runway, and derives the largest complete prefix using 68 pt rows plus 12 pt spacing. There is no three-row cap; measurement updates suppress animation, and non-empty supported portrait layouts retain at least one row.
- The `Today` eyebrow is now 15 pt light text, matching the Hero fact line. The record-momentum scenario projects every non-encrypted fixture, and its Hero/statistics count is generated from that array with a localized `%lld` format in English, Simplified Chinese, and Traditional Chinese.
- Replaced the full-width Today footer with a left-aligned, intrinsic-width 44 pt Glass pill. It uses the selected category tint, a restrained white backing in normal transparency, and an opaque semantic fallback when Reduce Transparency is enabled.
- Record detail now owns an unconditional full-screen opaque system-background layer. Its matched-geometry surface is a separate decorative rectangle; while detail is open, the mounted source page is faded out, cannot receive input, and is hidden from accessibility without losing Records query or scroll state.
- Unselected Records filter capsules now receive a white mask over their semantic fill (`0.46` light / `0.12` dark, increased for Reduce Transparency). Selected capsules remain unchanged solid category colors, and the pinned header outside the controls stays transparent.
- Added/updated tests for one through five fitted rows, no three-row cap, data clamping, larger measured Dynamic Type content, fixed 68 pt strips, the intrinsic 44 pt action pill, record-momentum count consistency, unselected-only filter masks, and opaque detail pixels over a high-contrast source for both Today and Records origins.
- Verification: all NewUIPreview sources and the four focused test files pass Swift parsing. The complete preview source set type-checks against the iPhoneOS SDK and the real MarkdownUI module in both normal and `NOTIEE_PLUS` configurations; all four test files also type-check against a temporary testable module. `git diff --check`, project plist lint, and all three localization plist lints pass. Focused XCTest and separate Notiee/Notiee+ builds were attempted with independent DerivedData but stopped before app/test source compilation because CoreSimulator is unavailable and the managed environment rejects SwiftPM manifest `sandbox-exec`. Simulator/device visual QA remains required for actual row counts at screenshot/small-screen heights, capture-gesture runway, detail transition opacity, and filter contrast. No commit or push was created.

### 2026-08-05 — Reworked NewUIPreview Today, Records filters, and transitions _(both targets; experimental preview only)_

- Added a literal `Today` eyebrow to all five Hero contexts and made active-event Aurora use the canonical Notiee green `#09C576`. Aurora is rendered only for the active-event context and pauses while Today is not the active destination.
- Removed the duplicate Hero shortcut rail. Today now presents up to three fixed 68 pt record/todo/schedule strips plus a contextual 44 pt “View All” action. Short screens reduce the visible preview count to two or one so the action and capture runway remain above the persistent Dock; full data remains available through the destination/module action.
- Added preview-only photo/audio/text/Spark sources, stable audio and Spark fixtures, and a dedicated fixed-size waveform/microphone treatment for audio cards. Records search and the five Mail-style expanding source filters compose by intersection; encrypted fixtures can remain in non-sensitive source categories but are excluded whenever search text is non-empty.
- Records now uses the system large navigation title and a transparent pinned search/filter header. Today and Records remain mounted behind one root Dock and use sibling fade/offset transitions. Todo/schedule modules push from the trailing edge with a subtle source-page transform. Record details use origin-aware matched geometry on the card background only; Reduce Motion disables geometry, offsets, and scaling.
- Added state coverage for source filters, search/filter intersection, stable audio/Spark IDs, encrypted isolation, Aurora eligibility, origin-aware detail routing, and Records query/filter persistence across detail and sibling-page round trips. Added `NewUIPreviewTodayLayoutTests.swift` for fixed strip geometry and compact-height item limits, and registered it in `NotieeTests`.
- Verification: the complete NewUIPreview source set type-checks against the iPhoneOS SDK and the real MarkdownUI module in both normal and `NOTIEE_PLUS` configurations. The updated state, masonry, and Today layout tests also type-check against a temporary iOS Simulator testable module. Swift parse checks, `git diff --check`, project plist lint, and all three localization plist lints pass.
- Focused XCTest and both scheme builds were attempted but stopped before app/test source compilation: CoreSimulatorService is unavailable, fresh DerivedData cannot fetch GitHub packages, and Xcode's SwiftPM manifest sandbox cannot run in the managed environment. The sandbox escalation service rejected the external test request. Simulator/device visual QA remains required for large-title collapse, sticky controls, transitions, compact-height Today layout, Dynamic Type, VoiceOver, Reduce Motion, and Reduce Transparency.
- Scope is limited to the shared NewUIPreview laboratory, its tests, localization, project registration, and this handoff. Production Today/Records/detail, `NotieeStore`, persistence, transport, and assets are unchanged. No commit or push was created.

### 2026-08-05 — Made the pinned Records search header transparent _(both targets; experimental preview only)_

- Removed the nearly opaque semantic background from the pinned Records search header. The search capsule keeps its interactive Liquid Glass treatment and pinned behavior, while the surrounding band is now transparent instead of rendering as a white rectangle in light mode.
- The change is limited to the shared `NewUIPreviewRecordsView.swift` and affects both Notiee and Notiee+. Production Records, search behavior, navigation, persistence, localization, and assets are unchanged.
- No commit or push was created. Simulator/device visual QA remains required because the managed environment cannot run CoreSimulator builds.

### 2026-08-05 — Rebuilt NewUIPreview Records layout containment _(both targets; experimental preview only)_

- Reworked the shared Records preview so the viewport computes one explicit content/column width contract (16 pt page insets, 12 pt column spacing) and passes the resulting width through the masonry layout, every card, and every media template. Accessibility Dynamic Type still switches the same layout to one full-width column.
- Removed the masonry cache that could reuse stale frames for same-count content changes. The custom `Layout` now remeasures current subviews for both sizing and placement while preserving shorter-column assignment, left-column tie breaking, and source-order accessibility traversal.
- Cards now enforce an exact outer width and a `cardWidth - 24` content width. Regular card timestamps use contextual precision (time today, month/day within the year, full date across years) and fall back to a vertical status/date arrangement when the horizontal header does not fit. Event/folder metadata is one truncating line.
- Replaced nested infinitely expanding media stacks with pure, testable CGRect geometry for 0/1/2/3/4/5+ images. Single images clamp aspect ratio and height; two-image, one-large-plus-two, and 2x2 templates use the passed content width; 5+ retains the final `+N` overlay. Images clip only inside their assigned media rectangles.
- Records now uses a pinned `LazyVStack` section header: the large `记录` title scrolls away, the Glass search field remains pinned, and the pinned band has an opaque semantic background. The navigation-bar background is visible only for the Records destination, preventing lab controls from covering cards; Today keeps its transparent/Aurora treatment. The 124 pt bottom content inset and overlay-based detail navigation remain.
- Extended `NewUIPreviewMasonryLayoutTests` with 320/375/428 pt-derived column widths, accessibility single-column width, media bounds/non-overlap checks at four content widths, and `UIHostingController.sizeThatFits` checks for completed 6-image, failed, pending, processing, and encrypted cards.
- Verification: affected Records/model sources type-check against the iOS Simulator SDK in both normal and `NOTIEE_PLUS` configurations; the updated test source type-checks against a temporary testable Notiee module; RootView and tests parse; `git diff --check` and project `plutil -lint` pass. A real scheme build was attempted with cached package checkouts but stopped before source compilation because the managed sandbox cannot access CoreSimulator or SwiftPM caches; the required sandbox escalation service also failed. The updated XCTest suite could not be executed, and simulator/device visual QA remains required.
- No production Records, data store, persistence, detail data, localization, asset, target membership, backend, or BYOK path changed. No commit or push was created. Existing uncommitted Today/HANDOFF work was preserved.

### 2026-08-05 — Investigated broken Records masonry rendering _(both targets; diagnosis only)_

- The two device screenshots show the same stable failure rather than a transient animation: processing/encrypted cards remain within their columns, while regular, failed, and multi-image cards expand beyond the proposed column width and overlap the adjacent column.
- Primary cause: `NewUIPreviewMasonryLayout` computes correct equal-width frames, but `placeSubviews` only proposes that width. `NewUIPreviewRecordCard` does not enforce it, and the regular branch contains an unbreakable state/date header plus media views that expand with infinite maximum dimensions. SwiftUI proposals are advisory, so those cards render at their larger ideal width even though the masonry geometry continues placing the next column at the calculated x-coordinate.
- Secondary structural issues: Records title/search live inside the scrolling content even though the approved plan calls for a persistent search field; the root navigation toolbar background is hidden, so menu/scenario controls visibly cover cards after scrolling. The masonry cache keys only width and subview count, so same-count search replacements or content-size changes can reuse stale heights.
- Current tests cover only the pure rectangle allocator with synthetic `CGSize` values. They do not integrate the SwiftUI `Layout`, real record cards, localized timestamps, media variants, viewport widths, cache invalidation, or overflow assertions. Simulator visual QA never ran in the managed environment, which is why the integration failure was not caught before the feature commit.
- Recommended redesign boundary: make the viewport own an explicit content width; have the masonry and every card/media variant accept and enforce the derived column width; compact or vertically restructure the timestamp header; move persistent page chrome outside the scrolling masonry; and add real-card layout/snapshot coverage at small/large iPhones, three locales, and accessibility sizes. Do not treat clipping or smaller fonts as a sufficient fix.
- No Swift, project, localization, or asset file was changed during this investigation. The issue affects the shared NewUIPreview implementation in both Notiee and Notiee+; production Records remains untouched.

### 2026-08-05 — Made the Today category row non-scrollable _(both targets; experimental preview only)_

- Removed the Today `记录 / 待办 / 日程` selector's horizontal `ScrollViewReader`/`ScrollView`. The three categories now stay visible in one fixed `HStack`, while each button still animates between icon-only and icon-plus-title states.
- The Hero shortcut rail remains independently horizontally scrollable because it is a separate command row; the lower Today selector no longer requires a swipe to reveal or reach any category.
- The change is limited to the shared `NewUIPreviewTodayView.swift` and applies to both Notiee and Notiee+. Production Today and all capture/data paths remain untouched.
- Verification still relies on SDK type checks and static validation because the managed environment cannot run simulator XCTest or visual QA.

### 2026-08-05 — Refined Today shortcut rail and spacing _(both targets; experimental preview only)_

- Reworked the Hero `记录 / 待办 / 日程` commands into a compact horizontally scrollable capsule rail. Each command now sizes to its icon, title, and optional non-zero count badge instead of being forced into an equal-width tile; this keeps the commands readable while preserving full capsule hit regions and semantic tinting.
- Kept the lower Today selector as the only content switcher. Added modest vertical spacing between the Hero, shortcut rail, selector, and Today rows so the fixed dashboard feels less cramped without consuming the reserved lower camera/audio gesture runway.
- The change is limited to `NewUIPreviewTodayView.swift`, shared by the Notiee and Notiee+ app targets. Production Today, Records, persistence, and capture pipelines remain untouched.
- Verification for this follow-up: the normal and `NOTIEE_PLUS` NewUIPreview SDK type checks, `git diff --check`, and `plutil -lint Notiee.xcodeproj/project.pbxproj` pass. A focused `xcodebuild test` was attempted but stopped before source compilation because CoreSimulator is unavailable and the sandbox cannot resolve the SwiftPM package graph; simulator interaction/visual QA remains pending.

### 2026-08-05 — Today layout density and Hero shortcut discussion _(both targets; design discussion only)_

- The supplied Today screenshot exposes a hierarchy problem rather than only a spacing problem: the Hero shortcut row currently reads like `9 / 0 / 0` statistics, while the Today selector repeats the same `Records / Todos / Schedule` concepts below it. The fixed Today surface intentionally leaves a lower capture-gesture runway, so that blank area should remain quiet instead of being filled with more cards.
- Recommended next direction: keep the Hero as title plus factual row, convert its three full-module shortcuts into one compact horizontal action rail (`icon + short title`, with a small non-zero count badge only when useful), and keep the lower expandable selector solely responsible for switching bounded Today content. Use soft semantic fills or restrained Glass grouping for the action rail, with distinct record/todo/schedule tints; do not use icon-only Hero actions because their meaning is ambiguous on iPhone.
- No Swift or project files were changed for this discussion. Wait for product confirmation of the compact capsule action rail before implementing the layout adjustment. Target classification remains shared Notiee + Notiee+, experimental NewUIPreview only.

### 2026-08-05 — Restored Today capture gesture hit region _(both targets; experimental preview only)_

- Fixed the Today camera/audio drag hit area by applying an explicit full-rectangle `contentShape` after the dashboard's bottom padding and before its parallel gesture. The lower transparent dashboard area now participates in hit testing, while the Dock and child controls remain above it and retain their own taps.
- The existing state guard still disables capture while the Spark composer, an overlay, or a non-Today destination is active. Both normal and `NOTIEE_PLUS` NewUIPreview SDK type checks pass, and `git diff --check` passes. Simulator gesture QA remains pending because CoreSimulator is unavailable in the managed environment.

### 2026-08-05 — Corrected Today category switcher _(both targets; experimental preview only)_

- Replaced the equal-width Today `记录 / 待办 / 日程` segmented row with a custom horizontally scrollable `ScrollViewReader` picker. Unselected categories render only their SF Symbol; the selected category expands to icon plus localized title, using its own tint and semantic secondary fill for the collapsed state.
- Selection changes are wrapped in a snappy animation and the selected item is centered through `scrollTo`, so the button width, neighboring positions, and the existing Today content below it transition together. Accessibility labels and selected traits remain explicit.
- Verification: the full NewUIPreview Swift source set type-checks with both the normal configuration and `NOTIEE_PLUS` defined; `git diff --check` passes. Runtime simulator/visual QA remains subject to the CoreSimulator and SwiftPM sandbox limitations recorded below.

### 2026-08-05 — NewUIPreview Today / Records / detail implementation _(both targets; experimental preview only)_

- Implemented `docs/superpowers/plans/2026-08-05-new-ui-preview-today-records-detail.md` inside the shared `Notiee/Features/Settings/NewUIPreview/` laboratory. Production Today, Records, Record Detail, `NotieeStore`, persistence, backend, subscription, and BYOK transport were not changed. No `#if NOTIEE_PLUS` branch or backend-only dependency was added.
- Added stable mock fixtures and preview routing/state. Fixed UUIDs and a fixed reference date cover all five Hero contexts, empty/non-empty Today states, 0/1/2/3/4/5/6-image records, landscape/portrait media, empty summary, OCR, todos, pending/processing/failed/encrypted records, summary-only Records search, encrypted redaction, and overlay-based detail navigation that preserves the underlying Records query/scroll view.
- Rebuilt Today as a non-scrolling, unframed contextual dashboard with light/dark calibrated active-event Aurora, equal Glass module shortcuts, Hero-selected daily tabs, up to three type-specific rows, media thumbnails for daily records, lightweight empty states, and a parallel capture gesture that no longer sits in a hit-testing foreground layer. The full todos/schedule overlays are mock-only and todo IDs are deduplicated.
- Added the Records destination with a pure shorter-column masonry geometry helper plus SwiftUI `Layout`, Dynamic Type single-column fallback, persistent root Dock, search/empty states, summary-only cards, 0/1/2/3/4/5+ media templates, protected encrypted cards, fixed-size pending/processing placeholders, and navigable failed records.
- Added the overlay Record Detail reading layer with fixed Glass controls, media hero/pager/full-screen viewer, pinned organized/raw/todos selector, MarkdownUI document projection, duplicate-summary suppression, current-tab search highlighting, encrypted redaction, a 480 pt scroll-to-top threshold, safe bottom content padding, mock append composer, and medium/large Emergence sheet. Toolbar controls were compacted to fit small screens while retaining at least 44 pt icon hit targets.
- Updated the Glass helper for Reduce Transparency, native iOS 26 `GlassEffectContainer`, and a more opaque iOS 18 `.regularMaterial` fallback. Added all new visible control/status strings to `en`, `zh-Hans`, and `zh-Hant` catalogs. Mock record body text intentionally remains user-content-like fixture data rather than localized product chrome.
- Added six original offline raster scene illustrations as `NewUIPreviewPhoto01...06` (five 1200x900, one 900x1200). The built-in image-generation tool was unavailable, so AppKit-generated local artwork was used; the stable asset names allow later photo replacements without Swift changes. All asset `Contents.json` files parse and reference valid PNG dimensions.
- Project membership is registered for both app targets for every new preview Swift file (and the existing preview Aurora Swift/Metal files); the three new test files are registered only in `NotieeTests`. `plutil -lint` passes for the project and all localization catalogs, all asset JSON parses, and `git diff --check` passes.
- Independent iOS Simulator SDK type checking passes for the real model dependencies plus every NewUIPreview Swift file, both with the normal configuration and with `NOTIEE_PLUS` defined. Swift syntax parsing passes for all three new test files. A real focused `xcodebuild test`, full Notiee tests, and both scheme builds could not reach source compilation: the managed sandbox cannot access CoreSimulator, Xcode's SwiftPM integration cannot start its nested `sandbox-exec`, and the escalation approval service failed. The installed Xcode also reports no downloaded Metal Toolchain. Do not claim XCTest, Metal compilation, app launch, or visual QA as passed.
- Remaining QA on a normal Xcode host: run the focused tests, full Notiee tests, and both scheme builds; then inspect iPhone 17 plus a smaller simulator in light/dark, accessibility Dynamic Type, VoiceOver, Reduce Motion, and Reduce Transparency. Exercise all five Heroes, capture gestures around every control, all media templates, Records search/empty states, detail sticky selector, pager announcements, scroll-to-top, bottom inset, and preservation after dismissing detail/Emergence.
- No commit or push was created.

### 2026-08-05 — Consolidated NewUIPreview Today/Records/detail design spec _(both targets; documentation only)_

- Added `docs/superpowers/specs/2026-08-05-new-ui-preview-today-records-detail-design.md`, consolidating the approved discussion into one implementation-ready design specification. No application source or production behavior changed.
- Scope is shared Notiee + Notiee+, experimental `NewUIPreview` only, mock-data-only. The spec explicitly leaves production Today, `RecordsView`, `RecordDetailView`, persistence, backend, subscription, and BYOK transport untouched.
- For NewUIPreview, this spec supersedes the old urgent/shared-review/statistics presentation with an unframed contextual Hero, full-module shortcuts, and bounded context-selected Today tabs. Existing Hero priority, capture gestures, active-event Aurora, and Today/Spark/Records shell remain.
- Records is specified as true two-column masonry with a Dynamic Type single-column fallback. Card body uses only `NoteRecord.summary` (title max two lines, summary max four; no detailed-content/OCR fallback), with real 0/1/2/3/4/5+ image templates and protected processing/encrypted states.
- Record detail is specified as fixed Glass toolbar + scrolling media/metadata + sticky `整理内容 / 原文 / 待办` selector + unframed document + fixed `追加记录 / 涌现` Glass actions. Single image uses an aspect-aware hero; multiple images use a full-width pager. `涌现` opens a floating sheet and is never called `发芽`.
- References determine layout only; iOS 26 native Liquid Glass remains the visual language for interactive chrome. Content, photos, masonry cards, and document text remain solid/unframed. The spec includes component boundaries, mock fixtures, accessibility requirements, non-goals, and acceptance criteria for both schemes.
- This is a design spec, not an executable implementation plan. No build was required; document review, referenced-spec existence checks, and whitespace validation passed.

### 2026-08-05 — NewUIPreview visual language confirmed as iOS 26 Liquid Glass _(both targets; discussion only)_

- The supplied references define layout, hierarchy, and scrolling behavior only. The actual NewUIPreview visual language must remain native iOS 26 Liquid Glass for both Notiee and Notiee+.
- Apply Glass primarily to interactive chrome: top toolbar controls, search, segmented selectors, secondary shortcuts, floating actions, and the persistent bottom dock. Keep photos, masonry record cards, article text, and the detail document surface visually solid/unframed so content remains legible; do not turn every surface into translucent glass.
- Use semantic system backgrounds and the existing Notiee accent rather than copying the references' beige/white palette. Light/dark appearance and Reduce Transparency must remain usable.
- Adjacent Glass controls should use the native iOS 26 grouping/container behavior where appropriate, explicit `contentShape`s, stable control dimensions, and full visible hit regions. This is especially important because the existing preview previously exposed flaky dock taps around incomplete hit regions.
- For record detail, the fixed toolbar, sticky content selector, bottom `追加记录 / 涌现` dock, and conditional scroll-to-top control are Glass; media, title metadata, and the long-form document scroll beneath them without decorative glass containers.
- No Swift source, localization, target membership, or production UI changed in this discussion.

### 2026-08-05 — NewUIPreview record-detail direction _(both targets; discussion only)_

- The user supplied three references for the new record-detail visual direction. Any later implementation remains shared between Notiee and Notiee+ but isolated to `NewUIPreview`; production `RecordDetailView` remains unchanged.
- Recommended scroll hierarchy: a fixed compact toolbar; media, title, creation time/status, and metadata chips scroll normally; a lightweight content-navigation strip becomes sticky; the document body scrolls beneath it; a bottom action dock remains above the safe area and reserves content inset. A scroll-to-top control appears only after meaningful downward progress.
- Use an unframed document surface with generous typography, Markdown-style headings/lists, and selectable text rather than stacking the current detail sections as rounded cards. The primary article can compose summary, detailed content, key points, definitions, and extracted todos; OCR remains a secondary/raw view rather than overview prose.
- Single-image detail uses one large aspect-aware hero image. Multi-image detail uses a full-width swipeable pager with position/count feedback so every image can be inspected; the masonry collage rules belong only to the Records overview. A record with no images starts directly at the title without a media placeholder.
- The reference's `发芽` must map to the already-approved Notiee feature name `涌现`. Preserve the existing product decision that Emergence opens a shared floating sheet over the detail rather than becoming a replacement content page. A suitable bottom dock is `追加记录` plus `涌现`, with no mascot.
- Metadata chips should derive from fields Notiee actually owns (record source, event, folder, processing state) rather than inventing unsupported AI tags. Search in the fixed toolbar, if retained, should search within the current long record.
- Open information-architecture choice: use a sticky content strip such as `整理内容 / 原文 / 待办`, while keeping Emergence as an action, versus copying the reference's three labels more literally. The former is recommended because it matches existing Notiee data and the approved Emergence flow.
- No Swift source, localization, project membership, persistence, or production detail behavior changed in this discussion.

### 2026-08-05 — NewUIPreview Records masonry direction _(both targets; discussion only)_

- The user supplied a reference for a redesigned Records destination and explicitly wants single-image and multi-image records to render differently. Any later implementation remains limited to the shared `NewUIPreview`; the production `RecordsView` is unchanged.
- Recommended page structure: retain the preview's own top navigation and bottom Today/Spark/Records dock, while borrowing the reference's large Records title, prominent search field, and true two-column masonry body. Do not copy unrelated upgrade controls or the reference app's bottom composer.
- Cards are content-driven and independently sized, not uniform grid cells. A normal row-aligned `LazyVGrid` would leave gaps beside tall cards; implementation should use a real masonry/custom `Layout` that assigns each card to the currently shorter column. Accessibility text sizes should fall back to one column.
- Proposed media rules: zero images -> text card; one image -> one focal preview that respects/clamps the source aspect ratio and may dominate an image-only card; two images -> side-by-side pair; three images -> one large plus two stacked; four or more -> 2x2 collage with `+N` on the final tile. Multi-image cards must render actual additional images rather than the production thumbnail's current first-image-plus-gray-stack hint.
- Card information hierarchy: timestamp/status, title, bounded summary, media, then tags. The overview body must read only `NoteRecord.summary`, with no fallback to `detailedContent` or `ocrText`; omit the body when the summary is empty. Recommended visual caps are two title lines and four summary lines with tail truncation. Encrypted and processing records need dedicated locked/loading templates that do not leak content.
- Existing `NoteRecord.localImagePaths: [String]` already supports these variants; no persistence migration is needed. Current production `RecordThumbnailView` loads only the first image, so a future production adoption would require a separate multi-image loader, but that is outside this preview-only phase.
- No Swift source, project membership, localization, or production Records behavior changed in this discussion.

### 2026-08-05 — NewUIPreview Today shortcuts and daily tabs direction _(both targets; discussion only)_

- The user wants to retain three compact secondary shortcuts for Schedule, Todos, and Records, plus a separate three-way switch below the Hero for Today's Records, Today's Todos, and Today's Schedule. Any later implementation remains limited to the shared `NewUIPreview` laboratory UI; production Today is unchanged.
- Recommended information architecture: Hero answers what matters now; shortcut tiles navigate to the complete content modules; the daily tabs switch only the bounded content shown inside Today. Use explicit full-scope versus today-scope labels where necessary so the two layers do not feel duplicated.
- The tabbed daily area should replace the current urgent/shared-review/statistics stack rather than be added after it. Hero-relevant content can become the initial selected tab (active/imminent event -> Schedule, due todo -> Todos, record momentum/calm -> Records), while a manual tab selection should remain stable during that visit.
- Preserve the fixed, non-scrolling dashboard and vertical capture gestures: show at most roughly three items per daily tab, with full results available through the secondary shortcuts. A vertically scrolling tab body would conflict with the existing pull-down camera and pull-up audio gestures.
- Borrow the references' segmented-switch interaction, but render each content type appropriately: records may use thumbnails, todos need check/state/deadline rows, and schedules need time-oriented rows. Do not force all three into the same image-card grid.
- Open product detail: confirm whether the context-driven initial tab should be adopted or whether Today's Records should always be the default. No Swift source, target membership, or production behavior changed in this discussion.

### 2026-08-05 — NewUIPreview Today header direction under discussion _(both targets; discussion only)_

- The user supplied a visual reference for the top of Today and explicitly scoped any later implementation to `Notiee/Features/Settings/NewUIPreview/`; production Today remains untouched.
- Direction so far: borrow the reference's unframed, text-led hierarchy, but omit both the mascot and the large white rounded rectangle. Replace the current icon-bearing Hero card with a large left-aligned contextual headline directly on the page background, followed by a lighter factual/status row.
- Preserve Today 2.0 semantics rather than copying the reference's memory-count information architecture: the deterministic Hero still answers what matters now; the secondary row can express event progress, deadline, record momentum, or a calm capture invitation. The active-event Aurora remains a background atmosphere behind this header, not a container.
- Target classification for a later implementation: both Notiee and Notiee+, experimental NewUIPreview only. No Swift source or production UI was changed in this discussion. Open design choices remain the exact secondary-row treatment and whether the header should have a small semantic eyebrow.

### 2026-07-29 — Active-event Aurora implemented in NewUIPreview _(both targets; experimental preview only)_

- Added `NewUIPreviewAuroraView.swift` and `NewUIPreviewAurora.metal`, registered both in the Notiee and Notiee+ source build phases. The SwiftUI wrapper hosts a transparent `MTKView`; the Metal shader ports the supplied Aurora simplex-noise/color-ramp approach and uses premultiplied-alpha blending.
- `NewUIPreviewTodayView` mounts the Aurora only for `.activeEvent`, under the dashboard content, fixed to the top 280 pt and with hit testing disabled. The fragment shader fades its lower edge so the effect does not become a page background.
- `NewUIPreviewHero` now carries optional `auroraColorHex`. The active-event fixture supplies `EventTag.work.colorHex`; a missing/invalid value falls back to Notiee green (`#09C576`). Other Hero contexts do not create a renderer. This is still mock-only and does not read `NotieeStore`.
- Motion is capped at 30 fps. The renderer pauses outside an active scene and freezes a stable frame under Reduce Motion. A missing Metal device/library/pipeline hides the renderer without affecting the dashboard.
- Verification: `plutil -lint Notiee.xcodeproj/project.pbxproj`, `git diff --check`, Swift syntax parsing, and iOS Simulator SDK type checks for the new renderer/state/Today/Dock/Glass source set all passed. Direct Metal compilation is blocked because this Xcode lacks Metal Toolchain; the component-download approval request was rejected by the tool approval service. Both Notiee and Notiee+ builds were attempted but stopped before source compilation because the sandbox cannot resolve GitHub to fetch `OnboardingKit`. Visual/device QA remains required after installing the Metal Toolchain and restoring dependency access.
- No commit was created.

### 2026-07-29 — Active-event Aurora design approved for NewUIPreview _(both targets when implemented; documentation only)_

- Added `docs/superpowers/specs/2026-07-29-new-ui-preview-active-event-aurora-design.md`; no application source, target membership, localization, persistence, or backend behavior changed in this design task.
- Aurora is an experimental top-Hero visual only: it appears only for an active event, derives its single color family from the event tag color, and falls back to Notiee green when the event has no tag. All non-active Hero states render no Aurora.
- The approved implementation is a native Metal port of the supplied React Bits Aurora shader, hosted by a SwiftUI `MTKView` wrapper. It is capped at 30 fps, is non-interactive, pauses when inactive/offscreen, freezes for Reduce Motion, and fails closed when Metal cannot render.
- Preview stays mock-data-only. `NewUIPreviewHero.auroraColorHex` will exercise tagged and untagged active-event fixtures; future production Today work may source the same semantic input from `ScheduledEvent.tagID -> EventTag.colorHex`, but that integration is out of scope here.
- Required later QA: tag-color and fallback-green active events, zero Aurora for non-active contexts, light/dark readability, Reduce Motion, input passthrough, and both app scheme builds. User has not requested a commit.

### 2026-07-29 — Today 2.0 design spec and executable plan written _(both targets when implemented; documentation only)_

- Added `docs/superpowers/specs/2026-07-29-today-2-context-dashboard-design.md` and `docs/superpowers/plans/2026-07-29-today-2-context-dashboard.md`; no application source, project membership, persistence, backend, or localization file changed in this planning task.
- The plan implements the already agreed fixed-screen Context Dashboard as seven independently verifiable tasks: deterministic Hero resolver, fixed dashboard, two-destination root/migration, persistent Spark composer, camera prepare-vs-start split, pure pull reducer with camera route, then non-recording audio entry plus full verification.
- Locked phase-one thresholds for testable initial behavior: camera prepare at 18 pt, camera/audio arm at 88 pt, unused prepared-camera release after 750 ms. These are tuning constants requiring physical-device validation, not product copy.
- The plan explicitly preserves both target Spark transport paths, migrates legacy `capture`/`spark` launch defaults to `today`, and requires both app schemes plus physical iOS 26 gesture/camera QA before completion.

### 2026-07-29 — Today 2.0 skeleton inside NewUIPreview _(both targets; experimental preview only)_

- Implemented the 2026-07-29 product-definition decisions inside the existing `Notiee/Features/Settings/NewUIPreview/` laboratory preview. This is NOT the production Today surface — it only previews the direction.
- `NewUIPreviewState.swift` rewritten: added `NewUIPreviewHeroContext` (.execution/.reflection/.calm), `NewUIPreviewHero`, `NewUIPreviewUrgentItem`, `NewUIPreviewTodayRecord`, `NewUIPreviewStatistics`, `NewUIPreviewSharedReviewSlot`, `NewUIPreviewCapturePhase` (.idle/.preflight/.armed/.canceling), `NewUIPreviewCaptureDirection`. Hero is rule-selected in `recomputeHero()` (active focus > near deadline > imminent reminder > meaningful today activity > calm). `sharedReviewSlot` adapts to Hero context (todos for execution, todayRecords for reflection, calm invitation otherwise). `statisticsVisible` hides first when space constrained (urgent >= 2).
- Capture gesture state machine: `beginCaptureDrag` → `.preflight` (preflight camera session concept); crossing `committedThreshold=0.6` → `.armed` + show camera affordance + one light `UIImpactFeedbackGenerator(.light)`; release while armed opens camera/audio-entry (toast only, no real capture); pulling back below `committedThreshold - cancelGrace=0.15` enters `.canceling` with 0.35s grace then resets. `captureGestureEnabled` is false while Spark/keyboard/sheet active (bound to `!isExpanded`).
- `NewUIPreviewTodayView.swift` rewritten: non-scrolling dashboard (VStack of Hero + urgent slot (max 2) + shared review slot + conditional statistics), bottom dock, transparent full-screen `NewUIPreviewCaptureGestureLayer` with a `DragGesture` that classifies direction by sign of translation.height and feeds progress into the state machine. The dock remains Today | Spark | Records; Spark still expands from bottom as a sheet. No ScrollView on the dashboard content.
- No production navigation, stored settings, backend behavior, or target-specific code changed. Both `Notiee` and `Notiee+` schemes BUILD SUCCEEDED on iPhone 17 simulator.
- Next agent: validate on the original iOS 26 device — (1) Hero card reflects the highest-priority mock item; (2) shared slot switches todos→records when Hero context changes; (3) pull down past ~84pt shows camera affordance + haptic, release opens camera toast, pulling back cancels; (4) pull up shows audio toast; (5) gestures disabled while Spark sheet is open. The mock data is static — wiring real `NotieeStore`/records is explicitly out of scope for this preview.

### 2026-07-29 — Today 2.0 product-definition decisions _(both targets when implemented; no source change)_

- Today 2.0 is a fixed-height, non-scrolling Context Dashboard, not a list, feed, or timeline. Its first-second job is to answer what matters most now.
- Hero is unique and rule-selected: deterministic priority chooses the focus; Spark only writes its title/supporting copy. The initial priority model is active focus > near hard deadline > imminent reminder > meaningful today activity > calm/recording invitation.
- The page uses bounded slots: Hero always remains; P1 urgent content can show up to two items; the shared review slot adapts to the Hero (execution context favors todos, reflection context favors today records); statistics disappear first when space is constrained.
- Bottom navigation direction remains Today | persistent central Spark composer | Records. Capture is an action, not a tab. Spark expands from the bottom with focused input and is not a standard tab.
- Today owns capture gestures. Downward pull opens camera; upward pull opens an audio-record entry only in the first release (no committed recording/transcription behavior). Interactive cards and controls keep gesture precedence; root gestures disable while Spark, a sheet, or keyboard is active.
- Downward camera gesture state: small downward movement preflights/configures the authorized camera session without activating its sensor; crossing the committed threshold starts the sensor, shows the camera affordance, and gives one light haptic; release while armed opens camera. Pulling back cancels and releases the prepared session after a short grace period. This deliberately balances first-frame latency with the camera privacy indicator.

### 2026-07-29 — New UI preview now follows the App color scheme _(both targets; experimental preview only)_

- Removed the preview's forced black backgrounds and `.preferredColorScheme(.dark)` override. Its background now uses `systemBackground`; primary, secondary, card, dock, and composer foreground colors use dynamic semantic colors.
- The experimental preview therefore follows the main app's existing light, dark, and system appearance setting. The send-arrow glyph remains black intentionally because it sits on the green circular accent control.
- No production navigation, stored setting, backend behavior, or target-specific code changed. Swift syntax parsing passed for all five modified preview source files; full Xcode scheme builds remain blocked by the sandbox's unavailable GitHub dependency resolution.

### 2026-07-29 — Corrected NewUIPreview dock hit regions; restored Glass interaction _(both targets; experimental preview only)_

- Follow-up device evidence established that the underlying issue was incomplete button hit regions, not a reason to remove native interactive Glass: the right half of the Spark capsule and the outer areas of both circular controls ignored taps.
- Restored `interactive: true` on all three dock Glass effects and added explicit `contentShape(Capsule())` / `contentShape(Circle())` to the corresponding button labels. The full visible capsule and circles now define the tappable area while retaining the iOS 26 Liquid Glass press effect.
- Scope remains shared Notiee + Notiee+ laboratory-preview code only. Validate on the original iOS 26 device by tapping the far-right edge of Spark and the outer edges of both circular controls.

### 2026-07-29 — Applied NewUIPreview dock tap reliability experiment _(both targets; experimental preview only)_

- Applied the smallest reversible change to the reported bottom-dock issue: `NewUIPreviewSparkDock` and `NewUIPreviewCircleButton` now use non-interactive Glass. They retain their visual appearance, hit areas, and `NewUIPreviewPressStyle`; the Spark composer close control remains interactive because it was not reported as unreliable.
- The change is scoped to the laboratory preview and does not touch `RootTabView`, user records, backend transport, or target-specific behavior. The preview sources are shared by Notiee and Notiee+.
- Static verification passed: `git diff --check` was clean, and the only remaining interactive-Glass call is the composer close control. A full Notiee build could not start because the sandbox could not resolve `OnboardingKit` from GitHub; one escalated build request was rejected by the approval service before execution. Validate on the original iOS 26 device: one tap each on Today, Spark, and Records should respond consistently.

### 2026-07-29 — Diagnosed NewUIPreview dock buttons needing multiple taps _(both targets; read-only investigation, no fix applied yet)_

- Symptom (user report): the three bottom dock controls in Settings → 实验室 → 新 UI 预览 (Today circle, Spark capsule, Records circle) show press feedback but require several taps before the tab actually switches / Spark expands; feels laggy.
- Root cause: iOS 26 Liquid Glass touch handling, two compounding factors in `Notiee/Features/Settings/NewUIPreview/`:
  1. `newUIPreviewGlass(in:interactive: true)` applies `.glassEffect(.clear.interactive(), in:)` to the **label inside** each `Button` (`NewUIPreviewGlass.swift`, used by `NewUIPreviewDock.swift`). Interactive glass has its own touch channel that operates independently of normal hit-testing (Apple Forums thread 816366: it reacts even when `allowsHitTesting(false)`). The visible "press feedback" is largely the glass's built-in micro-interaction, which fires on every touch regardless of whether the `Button`'s tap recognizer gets the sequence — so feedback shows while the action is dropped.
  2. Three adjacent interactive glass surfaces sit 14 pt apart in one `HStack` with **no `GlassEffectContainer`**. iOS 26 groups adjacent glass surfaces; the grouped gesture handling silently consumes/reroutes touches (documented gotcha), making off-center taps flaky. Explicit shapes (`Circle`/`Capsule`) mitigate but do not eliminate it.
- Why 100% reproducible here: deployment target is iOS 26, so the `#available(iOS 26)` glass path always runs; the pre-26 `.ultraThinMaterial` fallback has no touch side effects but never executes.
- Not the cause: `NewUIPreviewPressStyle` (plain isPressed animation), `NewUIPreviewState.select(_:)`'s `withAnimation`, ScrollView overlay ordering (dock is the top ZStack sibling), safe-area placement.
- Fix directions (NOT applied — user asked for diagnosis only): (a) move `glassEffect` from the label onto the `Button` itself so there is exactly one touch handler; (b) wrap the dock `HStack` in `GlassEffectContainer(spacing: 14)`; (c) optionally drop the custom press style (interactive glass already gives press feedback) or drop `.interactive()` if flakiness persists.
- Target classification: the six NewUIPreview files are in **both** Notiee and Notiee+ targets (two PBXBuildFile sets in project.pbxproj), so any fix affects both targets. Files are Lab-preview only; main-app UI untouched.

### 2026-07-29 — Read-only audit of `notiee-newfront` prototype _(no product-target change; no product source change)_

- `/Users/dxm/Documents/coding/notiee-newfront` is a separate Git repository containing a small Swift Package prototype for the planned three-part navigation: Today, a prominent central Spark dock, and Records.
- It contains seven SwiftUI source files (350 lines) implementing an iOS 26 native Liquid Glass dock, placeholder Today/Records content, and a bottom-entering Spark composer. It has no data/service integration, localization resources, tests, or connection to the main Notiee project.
- `Package.swift` declares only a library product and the sources contain `ContentView` but no `@main App`, so it is not currently a directly runnable iOS application despite `design-qa.md` instructing the reader to run it in a simulator. The reference image recorded in that QA file points to a temporary path that no longer exists.
- The prototype repository is on `main` at `e3d1114`; its only working-tree change is a tracked `Sources/.DS_Store`. Its ignored local `.build` directory accounts for almost all of the repository's 191 MB disk usage.

### 2026-07-28 — Product copy review: personal intelligence positioning _(no product-target change; no source change)_

- The existing end-state statement correctly emphasizes user-owned knowledge, experiences, and thinking style, but it frames the product as a static “structured memory body.” Future positioning should explicitly retain Spark/Agent capability: it should understand, reason from, converse with, and act through that personal context.


### 2026-07-24 — Product direction agreed: Spark Emergence _(both targets when implemented; no source change)_

- The planned personal-knowledge discovery feature is named **Emergence** (Chinese UI name: `涌现`), powered by Spark. It must not be branded as “Sprouting” / `发芽`.
- Report vocabulary is fixed: `起点` (core proposition), `脉络` (connections), `新见` (new insight; replaces “Aha moment”), `回声` (a resonant source sentence and extension), `未竟` (open questions / blind spots), and `来源` (verifiable references). Daily aggregation is `今日涌现`.
- Product promise: “not merely similar notes”; it explains why selected records connect and what new perspective arises. Copy approved for the feature: “Spark Emergence is Notiee’s personal knowledge-discovery capability: starting from one or more records, it connects historical notes, relevant theory, and trustworthy sources to reveal connections that were not previously explicit.”
- Entry points: (1) a `涌现` toolbar icon immediately left of Share in a record detail; (2) `涌现` action in record-library multi-select; (3) a conditional daily `今日涌现` notification (default 20:00, user-disableable and only when enough meaningful candidates exist); (4) Spark detects an implicit desire for cross-note connections, patterns, blind spots, or extension and offers a user-confirmed suggestion, never starts analysis automatically.
- All entry points open one shared native bottom-sheet/floating `涌现` experience, retaining the underlying detail, list, or Spark conversation rather than navigating to a separate Spark screen. The user confirms the selected record scope before generation. The sheet can offer “continue in Spark” after the report. Existing “Deep Association Mode” UI is weak (opaque top-3 semantic-similarity links); retain its local vector capability only as an Emergence candidate-retrieval layer, and replace its user-facing experience rather than exposing raw recommendations.
- Future implementation is shared UI/domain behavior in both targets. Transport remains isolated: Notiee free calls the SCF-backed Spark/AI path; Notiee+ calls the user-configured provider directly.

### 2026-07-24 — Diagnosed Korean/Japanese vision-note false failures _(free target only; no source change)_

- SCF successfully completed both reported `POST /ai/process` requests (HTTP response with `content`, `tokensUsed`, and quota; 40-55 seconds), so the fault is after the backend response rather than OCR, model generation, quota, or SCF timeout.
- In both captured model payloads, `definitions` is a JSON array of strings such as `"全国両会：中国の..."` / `"토지대장: ..."`. `RealAIProcessingService.parseStructuredNote` instead decodes it strictly as `[ParsedDefinition]`, where each element must be an object with `term` and `explanation` (`Notiee/Services/RealAIProcessingService.swift`). `JSONDecoder` therefore throws a type mismatch; `BackendAIProcessingService` propagates it and `AIPipelineManager` marks the record `.failed`.
- The prompt asks for objects, but model output is not schema-enforced, so foreign-language output exposed an existing parser robustness gap rather than a Korean/Japanese OCR problem. A future fix should add a failing parser test using this exact string-array shape, then tolerate both object and string definitions (or omit malformed definitions) without discarding the valid title/body. The shared parser is also used by Notiee+; any parser fix affects both targets, even though this incident is on the free SCF path.

### 2026-07-23 — AI latency root-cause audit _(no product-target change; read-only investigation)_

- **Classification:** no source/product change. The findings apply to the Notiee free-target backend path; the non-streaming Spark UI architecture is shared with Notiee+ (whose transport is direct-to-provider instead of SCF).
- **Note processing is structurally serial:** free client `BackendAIProcessingService.process` encodes up to 6 JPEG images/base64 and posts one large JSON body. Backend `/ai/process` awaits the vision call before it starts the text call (`vision = await callUpstream(...)`, then `textResult = await callUpstream(...)`). Both calls use the helper default `maxTokens = 4096`, are non-streaming, and each has a 60-second upstream timeout; client allows 180 seconds. Thus a normal visual note cannot complete faster than both complete responses plus image upload/SCF overhead. "Flash" applies only to the second text call; the first is `doubao-seed-2-0-mini` vision.
- **Spark plain chat is also non-streaming:** `/ai/chat` awaits one complete `callUpstream` result and returns JSON; `SparkViewModel` leaves an empty assistant placeholder until that response has fully arrived. It requests the same 4096 default max output. The UI has no per-hop duration/TTFB telemetry, and the backend has no upstream timings, so production delay cannot currently be attributed numerically between SCF and model.
- **Spark request work can be substantial before the model call:** every query runs semantic recall over all live records; first/changed records are embedded sequentially. Prompt assembly may include 15 recent anchors, up to 8 semantic full texts (800 chars each), 5 prior rounds (200+500 chars each), and up to 4000 chars of pinned cited content. Cloud embeddings are off by default; if enabled, they add one remote embedding for the query plus each cache miss.
- **Additional cases:** low-consumption note processing removes cloud vision but does accurate local Vision OCR sequentially per image with language correction across four languages before its one text call. Spark Agent is distinct from plain chat and can make up to 6 full non-streaming model calls (5 tool iterations plus a final summary), with external search/fetch potentially adding more delay.
- Production `GET /ping-stream` timing could not be measured in the audit environment: sandbox DNS failed and the required one-time unsandboxed read-only curl request was rejected by automatic approval infrastructure. Do not claim production SCF or provider timing until a device/production trace is captured. The checked-in backend may also differ from the deployed SCF artifact.

### 2026-07-23 — Shortcut screenshot input auto-connection fix pending device verification _(both targets)_

- User device feedback exposed a Shortcut UX defect: `NotieeScreenshotIntent` declared its `IntentFile` parameter with the default input behavior, so the action treated it as a standalone image-picker field and reported a missing screenshot instead of consuming the preceding system `Take Screenshot` output.
- Fixed `Notiee/Features/Capture/NotieeScreenshotIntent.swift` by adding `inputConnectionBehavior: .connectToPreviousIntentResult` to the image `@Parameter`. This is the App Intents API intended to auto-bind the immediately preceding action's result.
- Updated the screenshot-shortcut spec and implementation plan to require the same behavior. Existing shortcuts may cache their old action metadata; delete and re-add the Notiee action (or recreate the shortcut) after installing the updated build before device testing.
- Static verification: the source and docs contain the required enum case; `git diff --check` found pre-existing whitespace issues in `SystemPermissionManager.swift` and `en.lproj/Localizable.strings`, not in this intent edit.
- Both scheme builds were attempted but could not start because Swift Package resolution could not reach GitHub in the sandbox. Escalated Xcode network verification was automatically rejected by the environment. Do not claim a build or device result until a normal Xcode/physical-device validation is run.

### 2026-07-23 — Screenshot shortcut + background processing: ALL 5 TASKS COMPLETE _(both targets)_

- **17/17 tests PASS** (10 MockAIProcessingService + 5 AIPipelineRecovery + 2 ScreenshotImportService)
- **Both Notiee + Notiee+ BUILD SUCCEEDED**
- 5 tasks completed via subagent-driven development. Uncommitted on branch `feature/screenshot-shortcut-background`.
- New files: `AIBackgroundTaskScheduler.swift`, `NotieeProcessingRuntime.swift`, `ScreenshotImportService.swift`, `NotieeScreenshotIntent.swift`, `AIPipelineRecoveryTests.swift`, `ScreenshotImportServiceTests.swift`
- Modified: `AIProcessingState.swift`, `NoteRecord.swift`, `RecordManager.swift`, `NotieeStore.swift`, `AIPipelineManager.swift`, `NotificationManager.swift`, `SystemPermissionManager.swift`, `NotieeApp.swift`, `RootTabView.swift`, `LocalImageStore.swift`, both Info.plists, 3 Localizable.strings, project.pbxproj
- **Key architecture:** One shared `NotieeProcessingRuntime` owns a single `NotieeStore` for RootTabView + App Intent + BG task handler. `AIPipelineManager.process()` is the single async worker with in-flight dedup; terminal notifications are idempotent via `ProcessingNotificationState`. `NotieeScreenshotIntent` uses `openAppWhenRun = false`.
- **Bug fixed:** retry now enqueues directly — no longer changes state to `.pending` before calling a guard that rejects it.
- Device shortcut test not yet performed — see Task 4 Step 6 in the plan for the acceptance procedure.

### 2026-07-23 — Task 4 of screenshot shortcut: import screenshots via App Intents DONE _(both targets)_

- Created `ScreenshotImportService.swift` — `ScreenshotImportError` enum + `@MainActor struct ScreenshotImportService` with `importScreenshotData(_:) throws -> UUID`.
- Created `NotieeScreenshotIntent.swift` — `NotieeScreenshotIntent: AppIntent` (`openAppWhenRun = false`, `@Parameter` for image file) + `NotieeShortcuts: AppShortcutsProvider`.
- Created `ScreenshotImportServiceTests.swift` — `SpyImageSaver` (records calls, returns known path) + 2 tests (valid import saves before scheduling, invalid data throws without creating record).
- Added `@MainActor protocol ImageSaving` + `extension LocalImageStore: ImageSaving` to `LocalImageStore.swift`.
- Added 8 localization entries per language (en/zh-Hans/zh-Hant) near existing processing-status entries.
- Added pbxproj entries for all 3 files (both app targets for production files, test target for tests).
- **Pitfall:** Task brief pbxproj IDs conflicted with existing CreateItemSheet/ImportScheduleView IDs from Task 3. Used non-conflicting hex IDs (200000000000000000000037-039 / 100000000000000000000037-039).
- **Pitfall:** `AppShortcutsProvider.appShortcuts` uses `@AppShortcutsBuilder` result builder — single `AppShortcut` element with `[AppShortcut]` return type (not array literal `[AppShortcut(...)]`).
- **7/7 tests PASS** (2 ScreenshotImportService + 5 AIPipelineRecovery). **Both Notiee + Notiee+ BUILD SUCCEEDED.**
- Not committed.

### 2026-07-23 — Task 3 of screenshot shortcut: service files registration + Info.plist + tests DONE _(both targets)_

- Added pbxproj entries for `AIBackgroundTaskScheduler.swift` and `NotieeProcessingRuntime.swift` in both Notiee and Notiee+ targets (PBXBuildFile, PBXFileReference, Services group children, Sources build phases).
- Added `BGTaskSchedulerPermittedIdentifiers` + `UIBackgroundModes` (processing) to both `Notiee/Info.plist` and `Notiee copy-Info.plist`.
- Added `RecordingScheduler` class and `testRuntimeSchedulesAndRunsPendingProcessing` test to `AIPipelineRecoveryTests.swift`.
- **Fixed default parameter issue:** `NotieeProcessingRuntime` init had `.live()` and `AIBackgroundTaskScheduler.shared` as defaults — these trigger Swift concurrency warnings/errors because default parameter values are evaluated at the call site, not within the `@MainActor` context. Removed defaults; `shared` now passes both explicitly.
- **Fixed `scheduleProcessing()`:** now registers the handler with the scheduler before calling `scheduleProcessing()` (was only calling schedule; handler was never set up).
- **Logger:** `Logger.general.error(...)` in `AIBackgroundTaskScheduler.swift` compiles fine — `Logger` is in the same module and available without import.
- **5/5 tests PASS** (AIPipelineRecoveryTests). **Both Notiee + Notiee+ BUILD SUCCEEDED.**
- Not committed.

### 2026-07-23 — Task 2 of screenshot shortcut: terminal notification DONE _(both targets)_

- Added `ProcessingResultNotifying` protocol (`@MainActor`) to `AIPipelineManager.swift`.
- Added `notifier` property to `AIPipelineManager` (optional, nil by default).
- `process()` now delivers notification at all 3 terminal code paths (.completed, .failed via error, .failed via aiEnabled==false).
- `NotificationManager` conforms to `ProcessingResultNotifying`: checks permission, removes duplicate identifier, delivers immediate notification with localized title/body.
- `SystemPermissionManager` now requests notification permission after photo library in `requestAllPermissions()`.
- `NotieeStore` convenience init gained `notifier` parameter; `live()` sets `NotificationManager.shared`.
- 4 new localization entries in all 3 `.strings` files.
- 2 new tests (completed notification, failed notification) + spy notifier in `AIPipelineRecoveryTests.swift`.
- **14/14 tests PASS** (4 AIPipelineRecovery + 10 MockAIProcessingService). **Both Notiee + Notiee+ BUILD SUCCEEDED.**
- Not committed.

### 2026-07-23 — Task 1 of screenshot shortcut: AIPipeline repair + notification state DONE _(both targets)_

- Added `ProcessingNotificationState` enum (none/requested/delivered) to `AIProcessingState.swift`.
- Added `processingNotificationState` property to `NoteRecord` with safe `decodeIfPresent` fallback `.none`.
- Added `recordsNeedingAIRecovery()` and `setProcessingNotificationState(_:for:)` to `RecordManager`.
- Extended `AIPipelineRecordAccess` protocol with `recordsNeedingAIRecovery()`, `setProcessingNotificationState(_:for:)`, `eventTitle(for:)`.
- Rewrote `AIPipelineManager`: added `inFlightRecordIDs` set to prevent duplicate processing; extracted `process(recordID:localImagePaths:eventTitle:)` async worker with defer cleanup; removed `retryCount` param from `enqueueProcessing`; added `resumePendingProcessing()`.
- **Fixed retry bug:** `NotieeStore.retryAIProcessing` now guards on `.failed`/`.deadLetter` and calls `enqueueProcessing` directly — no longer changes state to `.pending` before calling `retryAndEnqueue` (whose guard would reject it).
- Added `NotieeStore.resumePendingAIProcessing()`, `captureShortcutScreenshot(localImagePath:)`, `processImportedScreenshot(recordID:)`.
- `processImportedScreenshot` always enqueues (skips `autoProcessAfterCapture` gate); `process` worker sets `.failed` when `aiEnabled` is false.
- Created `NotieeTests/AIPipelineRecoveryTests.swift` with 2 tests + pbxproj entries (test target only).
- **12/12 tests PASS** (2 new + 10 existing MockAIProcessingServiceTests). **Both Notiee + Notiee+ BUILD SUCCEEDED.**
- Not committed.

### 2026-07-23 — Corrected SCF deployment ZIP root layout _(free-target backend packaging only)_

- Tencent SCF rejected the first archive with `ResourceNotFound.Entryfile` because it searched for root-level `scf_bootstrap`, while the archive stored it as `notiee-ping-stream/scf_bootstrap`.
- Rebuilt and replaced the repository-root `notiee-ping-stream.zip` by archiving the **contents** of `notiee-ping-stream/`, not the directory itself. The ZIP root now contains `scf_bootstrap`, `index.js`, `package.json`, and `node_modules/`.
- Verified `unzip -tq` succeeds and `scf_bootstrap` retains executable mode (`-rwxr-xr-x`). The corrected upload artifact is 3.6 MB. Use this replacement archive for SCF.

### 2026-07-23 — Backend deployment ZIP created _(free-target backend packaging only)_

- Created `notiee-ping-stream.zip` at the repository root for Tencent SCF upload. It includes the complete `notiee-ping-stream/` directory, including `node_modules`, `index.js`, `scf_bootstrap`, `schema.sql`, package metadata, certificates, and the Node tests.
- ZIP validation via `unzip -tq` succeeded. Archive size is 3.7 MB (source directory is 17 MB).
- The archive matches the existing `.gitignore` rule `notiee-ping-stream*.zip`; it is deliberately not visible in normal Git status. Set `BOCHA_API_KEY` in SCF before deploying it.

### 2026-07-23 — Bocha search proxy implemented _(free-target backend only)_

- Implemented `POST /ai/search` in `notiee-ping-stream/index.js`. It requires the existing backend JWT and a `pro` user tier, validates `query` / `count` (1-10) / `freshness`, sends `summary: true` to `https://api.bochaai.com/v1/web-search`, and maps only `name`, `url`, `summary`, `snippet`, `siteName`, and `datePublished` into `{ results }`.
- Set `BOCHA_API_KEY` in the Tencent SCF function environment before deployment. Missing key returns `503 CONFIGURATION_ERROR`; a Bocha timeout/rejection returns `502 UPSTREAM_ERROR`; neither response includes the secret.
- Added Node built-in test coverage at `notiee-ping-stream/test/index.test.js`, plus `npm test` script. `node --check index.js && npm test` passed: **6/6 tests**. Tests are in-process and stub `fetch`; no outbound Bocha call is made.
- The backend directory is excluded wholesale by the repository `.gitignore` (`notiee-ping-stream/`), so its source and tests do **not** appear in `git status` and will not be included by a normal Git commit. Deploy/copy the edited directory explicitly; do not assume a mobile-app commit ships it.
- Notiee+ remains unchanged and continues to call Bocha directly with the user's Keychain-stored key. No iOS source changed and no Xcode build was needed.

### 2026-07-23 — Bocha backend proxy contract is not implemented _(no product-target change; read-only audit)_

- `Notiee/Features/Spark/Agent/Tools/WebSearchTool.swift` has a free-build path that calls authenticated `POST /ai/search` with `{ query, count, freshness }` and expects `{ results: [...] }`.
- `notiee-ping-stream/index.js` currently has no `/ai/search` route and no `bocha`/`BOCHA` configuration, provider, or upstream call. The backend proxy is therefore **not** present; free-build `web_search` will receive a 404 until it is added.
- Notiee+ is already wired independently: it calls `https://api.bochaai.com/v1/web-search` directly with the user's Keychain-stored API key.

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
