# Today 2.0 Context Dashboard Implementation Plan

> **For agentic workers:** Execute task-by-task with `superpowers:subagent-driven-development` or `superpowers:executing-plans`. Keep the checkboxes current.

**Goal:** Replace the scrollable Today timeline and four-tab root with a fixed Context Dashboard, persistent Spark composer, and Today-owned camera/audio-entry gestures.

**Architecture:** `TodayViewModel` stays as the Combine/store boundary. A pure resolver turns current events, todos, and records into `TodayDashboardState`; SwiftUI only renders that state. A custom root shell owns Today/Records plus a persistent Spark overlay. A pure gesture reducer emits effects, while the root coordinator performs haptic, camera, and presentation side effects.

**Tech Stack:** SwiftUI, Combine, AVFoundation, UIKit haptics, XCTest; iOS 18 deployment target with iOS 26 SDK.

**Spec:** `docs/superpowers/specs/2026-07-29-today-2-context-dashboard-design.md`

## Global Constraints

- Classification: shared UI/domain work for both Notiee and Notiee+. New shared Swift files must be added to both app targets; tests go only in `NotieeTests`.
- Keep free/Plus transport isolation in existing `#if NOTIEE_PLUS` paths. Never add ad-hoc runtime free/Plus checks.
- Add all visible keys to `Notiee/en.lproj/Localizable.strings`, `Notiee/zh-Hans.lproj/Localizable.strings`, and `Notiee/zh-Hant.lproj/Localizable.strings`.
- Do not migrate records or Spark conversations, call AI to choose Hero, add actual audio recording, or change backend contracts.
- Do not commit or push unless the user explicitly authorizes it. Update `HANDOFF.md` in English after implementation.
- Prefix every build command with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## File Map

| Path | Change | Purpose |
| --- | --- | --- |
| `Notiee/Features/Today/TodayDashboardState.swift` | Create | Pure Hero, bounded slots, and statistics value types. |
| `Notiee/Features/Today/TodayContextResolver.swift` | Create | Deterministic priority and cap logic. |
| `Notiee/Features/Today/TodayDashboardView.swift` | Create | Fixed-height Hero/urgent/review/statistic presentation. |
| `Notiee/Features/Today/TodayPullGestureReducer.swift` | Create | Testable pull state/effect reducer. |
| `Notiee/Features/Today/TodayAudioEntryView.swift` | Create | Non-recording phase-one audio surface. |
| `Notiee/Features/Today/TodayView.swift` | Modify | Detail navigation, dashboard callbacks, and root gesture binding. |
| `Notiee/App/RootTabView.swift` | Modify | Two-destination shell, camera route, Spark ownership. |
| `Notiee/App/RootNavigationDock.swift` | Create | Today/Records controls and central Spark action. |
| `Notiee/Features/Spark/SparkComposerOverlay.swift` | Create | Bottom-origin presentation and auto-focus wrapper. |
| `Notiee/Features/Spark/SparkView.swift` | Modify | Optional injected persistent `SparkViewModel`. |
| `Notiee/Features/Spark/SparkInputBar.swift` | Modify | One-shot external focus request. |
| `Notiee/Services/CameraManager.swift` | Modify | Prepare, start, and release camera session separately. |
| `Notiee/Features/Capture/CaptureView.swift` | Modify | Return to Today through an explicit completion closure. |
| `Notiee/Features/Capture/CaptureViewModel.swift` | Modify | Use the split camera lifecycle. |
| `Notiee/Models/AppTab.swift` | Modify | Retain only Today and Records destinations. |
| `Notiee/Services/UserDefaultsAppSettingsStore.swift` | Modify | Normalize legacy launch values. |
| `NotieeTests/TodayContextResolverTests.swift` | Create | Priority, cap, and fallback coverage. |
| `NotieeTests/TodayPullGestureReducerTests.swift` | Create | Gesture transitions and one-haptic behavior. |
| `NotieeTests/AppTabMigrationTests.swift` | Create | Persisted tab migration coverage. |
| `NotieeTests/CameraManagerLifecycleTests.swift` | Create | Prepare/start/release contract tests. |
| `Notiee.xcodeproj/project.pbxproj` | Modify | Both app target memberships for shared files; `NotieeTests` membership for tests. |

## Build Commands

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /private/tmp/notiee-today2-derived CODE_SIGNING_ALLOWED=NO

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project Notiee.xcodeproj -scheme Notiee+ \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /private/tmp/notiee-today2-derived-plus CODE_SIGNING_ALLOWED=NO
```

Expected final status: Notiee tests succeed and Notiee+ builds successfully. If dependency resolution is unavailable, report that fact rather than claiming a passing build.

### Task 1: Introduce the deterministic context model

**Files:**
- Create: `Notiee/Features/Today/TodayDashboardState.swift`
- Create: `Notiee/Features/Today/TodayContextResolver.swift`
- Create: `NotieeTests/TodayContextResolverTests.swift`
- Modify: `Notiee/Features/Today/TodayViewModel.swift`
- Modify: `Notiee.xcodeproj/project.pbxproj`

**Interfaces produced:**

```swift
enum TodayHero: Equatable {
    case activeEvent(ScheduledEvent)
    case dueTodo(NoteTodo)
    case imminentEvent(ScheduledEvent)
    case recordMomentum(count: Int)
    case calm
}

enum TodayReviewSlot: Equatable {
    case todos([NoteTodo])
    case records([NoteRecord])
}

struct TodayDashboardState: Equatable {
    let hero: TodayHero
    let urgentTodos: [NoteTodo]
    let urgentEvents: [ScheduledEvent]
    let review: TodayReviewSlot
    let todayRecordCount: Int
    let actionableTodoCount: Int
}

struct TodayContextResolver {
    static let dueSoonInterval: TimeInterval = 2 * 60 * 60
    static let imminentEventInterval: TimeInterval = 30 * 60
    func resolve(now: Date, events: [ScheduledEvent], todos: [NoteTodo], records: [NoteRecord], calendar: Calendar) -> TodayDashboardState
}
```

- [ ] Write a failing test suite with a fixed GMT+8 date: active event wins over overdue todo, overdue todo wins over imminent event, imminent event wins over records, three today records chooses momentum, and empty data chooses calm.

```swift
func testActiveEventWinsOverEveryOtherContext() {
    let state = resolver.resolve(now: now, events: [active, imminent], todos: [overdue], records: threeRecords, calendar: calendar)
    XCTAssertEqual(state.hero, .activeEvent(active))
}

func testCapsEverySupportingSlotAndExcludesHeroItem() {
    let state = resolver.resolve(now: now, events: events, todos: todos, records: records, calendar: calendar)
    XCTAssertLessThanOrEqual(state.urgentTodos.count, 2)
    XCTAssertLessThanOrEqual(state.urgentEvents.count, 2)
}
```

- [ ] Run the focused test target and confirm the initial compile failure references `TodayContextResolver`.
- [ ] Implement the resolver. Filter deleted records and completed todos; consider only today events. A due todo is overdue or due by `now + 2h`; an imminent event starts after `now` and by `now + 30m`. Exclude the Hero's own item from urgent slots. Use `TodoBucketer.isActionableNow` and cap every list at 2/3 exactly.
- [ ] Add `TodayViewModel.dashboardState`, calculated from its existing synchronized data. Keep `todayOverviewTodos` and `todayRecords` intact until Task 2 consumes the new state.
- [ ] Register new sources in both app targets and tests in `NotieeTests`; rerun `-only-testing:NotieeTests/TodayContextResolverTests`.

### Task 2: Render the fixed Context Dashboard

**Files:**
- Create: `Notiee/Features/Today/TodayDashboardView.swift`
- Modify: `Notiee/Features/Today/TodayView.swift`
- Modify: all three `Localizable.strings` catalogs
- Modify: `Notiee.xcodeproj/project.pbxproj`

**Consumes:** `TodayDashboardState` and closures for existing todo, event, record, account, and create actions.

**Produces:** `TodayDashboardView` with no `ScrollView`.

- [ ] Keep `TodayView` as the `NavigationStack`/detail-sheet owner; remove its timeline/section `ScrollView` and delegate visual content to `TodayDashboardView`.
- [ ] Use `GeometryReader` plus `VStack` so the dashboard has a stable maximum height. Header and Hero are permanent; urgent content has a hard maximum of two rows; review has a hard maximum of three; show statistics only at `proxy.size.height >= 680`.

```swift
GeometryReader { proxy in
    VStack(spacing: 12) {
        header
        TodayHeroCard(hero: state.hero)
        TodayUrgentSlot(todos: state.urgentTodos, events: state.urgentEvents, onTodoTap: onTodoInfo, onEventTap: onEventTap)
        TodayReviewSlot(slot: state.review, onTodoToggle: onTodoToggle, onTodoTap: onTodoInfo, onRecordTap: onRecordTap)
        if proxy.size.height >= 680 { TodayStatistics(state: state) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}
```

- [ ] Use resolver output only. Do not create a second business-priority switch in SwiftUI.
- [ ] Add localizations for Hero support copy, urgent/review labels, counts, and empty state in English, Simplified Chinese, and Traditional Chinese.
- [ ] Build Notiee and manually verify all five Hero states in Preview/debug fixtures: no vertical bounce, no clipping, and existing detail/toggle/navigation actions still work.

### Task 3: Replace the four-tab root and migrate launch settings

**Files:**
- Create: `Notiee/App/RootNavigationDock.swift`
- Modify: `Notiee/App/RootTabView.swift`
- Modify: `Notiee/Models/AppTab.swift`
- Modify: `Notiee/Services/UserDefaultsAppSettingsStore.swift`
- Modify: `Notiee/Features/Settings/SettingsMainView.swift`
- Create: `NotieeTests/AppTabMigrationTests.swift`
- Modify: `Notiee.xcodeproj/project.pbxproj`

**Interfaces produced:**

```swift
enum AppTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case today
    case records
}

struct RootNavigationDock: View {
    @Binding var selectedTab: AppTab
    let onSpark: () -> Void
}
```

- [ ] Write tests with an isolated `UserDefaults` suite. Assert `today`/`records` survive, while `capture`, `spark`, and invalid raw data load as `.today`; the two legacy raw values are rewritten as `today`.
- [ ] In `loadDefaultTab()`, migrate the raw string before decoding the narrowed enum. Remove `capture` and `spark` from `AppTab` and `launchCandidates`; Settings then naturally offers only Today and Records.
- [ ] Implement explicit dock buttons. Give every visual button its full `contentShape(Circle())` or `contentShape(Capsule())`; central Spark calls `onSpark` and never changes `selectedTab`.
- [ ] Replace `TabView` with a `ZStack` routing Today/Records and an overlaid dock. Preserve root store ownership, entitlement refresh, URL/TMN sheet, and `CameraControlOverlayView`. Route hardware Camera Control to a camera presentation state, not a removed capture tab.
- [ ] Register files, run migration tests, build both application schemes, and validate a device with legacy defaults.

### Task 4: Present Spark as a persistent bottom composer

**Files:**
- Create: `Notiee/Features/Spark/SparkComposerOverlay.swift`
- Modify: `Notiee/Features/Spark/SparkView.swift`
- Modify: `Notiee/Features/Spark/SparkInputBar.swift`
- Modify: `Notiee/App/RootTabView.swift`
- Modify: `Notiee.xcodeproj/project.pbxproj`

**Interfaces produced:**

```swift
struct SparkComposerOverlay: View {
    @ObservedObject var viewModel: SparkViewModel
    let store: NotieeStore
    @Binding var isPresented: Bool
}

init(store: NotieeStore, viewModel: SparkViewModel, focusRequest: UUID?)
```

- [ ] Refactor only ownership: retain the current Spark toolbar, sheets, background, Agent/model chips, send/stop behavior, and target-specific code. Add an injected-view-model initializer; `SparkView(store:)` remains for existing callers.
- [ ] Give `SparkInputBar` a one-shot `UUID?` focus request. On a fresh non-nil request it sets its existing local `@FocusState` on the next main-actor turn. It must not clear a draft or create a conversation.

```swift
.onChange(of: focusRequest) { _, request in
    guard request != nil else { return }
    DispatchQueue.main.async { isFocused = true }
}
```

- [ ] Root owns one `@StateObject SparkViewModel` created with the same managers as the former Spark tab. Present `SparkComposerOverlay` from the bottom and issue a focus UUID after the transition. Closing only hides the overlay.
- [ ] Manually verify draft persistence, in-flight response persistence, history, privacy sheet, Agent gating, keyboard focus, and both target model configurations.
- [ ] Register the new shared overlay and build both schemes.

### Task 5: Separate camera preparation from camera startup

**Files:**
- Modify: `Notiee/Services/CameraManager.swift`
- Modify: `Notiee/Features/Capture/CaptureViewModel.swift`
- Create: `NotieeTests/CameraManagerLifecycleTests.swift`

**Interfaces produced:**

```swift
protocol CameraSessionControlling: AnyObject {
    func prepareSession()
    func startPreparedSession()
    func releasePreparedSession()
}
```

- [ ] Write tests using a spy controller: short pull calls only prepare; armed release calls start before presentation; cancellation releases exactly once; the full Capture screen prepares then starts.
- [ ] Refactor `CameraManager`: `prepareSession()` checks permission and configures inputs/outputs without `session.startRunning()`; `startPreparedSession()` starts only configured sessions; `releasePreparedSession()` stops the sensor but preserves the configured session for a quick rearm. Preserve simulator readiness behavior.
- [ ] Update Capture lifecycle: `onAppear()` prepares then starts; `onDisappear()` releases. Remove every call to `checkPermissionsAndConfigure()`.
- [ ] Run focused tests and physical camera validation: no privacy indicator for short pull, fast preview on armed release, old permission handling remains valid, and leaving camera stops the indicator.

### Task 6: Implement the pull gesture reducer and camera route

**Files:**
- Create: `Notiee/Features/Today/TodayPullGestureReducer.swift`
- Create: `NotieeTests/TodayPullGestureReducerTests.swift`
- Modify: `Notiee/Features/Today/TodayView.swift`
- Modify: `Notiee/App/RootTabView.swift`
- Modify: `Notiee/Features/Capture/CaptureView.swift`
- Modify: `Notiee.xcodeproj/project.pbxproj`

**Interfaces produced:**

```swift
enum TodayPullEffect: Equatable {
    case prepareCamera, startCamera, lightHaptic, cancelCameraPreparation
    case presentCamera, presentAudioEntry
}

struct TodayPullGestureReducer {
    static let preparationThreshold: CGFloat = 18
    static let commitmentThreshold: CGFloat = 88
    mutating func changed(translationY: CGFloat, interactiveContentIsActive: Bool) -> [TodayPullEffect]
    mutating func ended(translationY: CGFloat) -> [TodayPullEffect]
}
```

- [ ] Write reducer tests: 17 pt does nothing; 18 pt prepares only; 88 pt starts plus one haptic; continued pull does not duplicate start/haptic; armed release presents camera; backing below 88 pt cancels; active child suppresses all effects. Negative threshold crossing emits one light haptic, and its armed release emits only the audio-entry effect.
- [ ] Implement the reducer as side-effect-free state. It owns no timer, AVFoundation, UIKit, or SwiftUI binding.
- [ ] In `TodayView`, bind a vertical drag after child controls have priority. Convert effects through closures to camera preparation/start/release, light haptic, and presentation. Disable the root gesture while sheets, navigation, Spark, keyboard, or card controls are interactive.
- [ ] Route camera from `RootTabView` with `fullScreenCover`. `CaptureView` receives `onExitToToday` so close/completion restores the unchanged Today route. Hardware Camera Control uses the same path.
- [ ] Keep the 750 ms unused-preparation grace task in the root coordinator, cancel it when a new pull begins, and never stop a visible full-screen camera.
- [ ] Register sources, run focused tests, build both targets, then device-test edges/center taps, repeated pulls, cancellation, denied permission, return flow, and one haptic per threshold crossing.

### Task 7: Ship the non-recording audio entry and final verification

**Files:**
- Create: `Notiee/Features/Today/TodayAudioEntryView.swift`
- Modify: `Notiee/Features/Today/TodayView.swift`
- Modify: `Notiee/App/RootTabView.swift`
- Modify: all three `Localizable.strings` catalogs
- Modify: `Notiee.xcodeproj/project.pbxproj`
- Modify: `HANDOFF.md`

- [ ] Implement a dismissible audio-entry surface with a microphone/waveform affordance and explicit unavailable state. Do not import `AVAudioRecorder`, request microphone permission, write files, or mutate `NotieeStore`.
- [ ] Present it from the same root coordinator for `.presentAudioEntry`. Verify upward-only triggering, below-threshold cancellation, one haptic, and no microphone privacy prompt/indicator.
- [ ] Register the new source in both targets and localize every new visible string.
- [ ] Run the complete Notiee test suite, then build Notiee and Notiee+ with the common commands. Run `git diff --check`.
- [ ] Perform physical iOS 26 QA: light/dark/system colors, iPhone 17 plus a smaller phone, Dynamic Type, VoiceOver labels/hit targets, all Hero priorities, bounded content/no scroll, keyboard focus, Spark state persistence, camera privacy timing, and Camera Control.
- [ ] Update `HANDOFF.md` in English with target classification, migration behavior, final thresholds, verification evidence, and any physical-device-only risks. Commit only if separately requested.

## Self-review

Each product rule maps to a task: priority/caps (1), fixed screen (2), navigation/migration (3), persistent Spark (4), camera preflight (5), downward pull (6), upward audio entry and both-target verification (7). The plan intentionally excludes focus-session persistence, AI Hero choice, audio recording, and transport work.
