# Screenshot Shortcut Background Processing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Accept a screenshot from a system Shortcut without presenting Notiee, make it into a durable photo record, continue AI processing under iOS background scheduling, and send a terminal local notification.

**Architecture:** A persisted `NoteRecord` is the only durable queue. One runtime shares a single live store between RootTabView, the App Intent, and the background-task callback. The pipeline serially recovers pending work and owns terminal state plus notification delivery; its existing free/Plus service factory remains unchanged.

**Tech Stack:** Swift 6, SwiftUI, XCTest, App Intents, BackgroundTasks, UserNotifications, UIKit, iOS 18.

**Spec:** `docs/superpowers/specs/2026-07-23-screenshot-shortcut-background-processing-design.md`

## Global Constraints

- **Target classification:** shared feature, affecting both Notiee and Notiee+. Do not add a runtime free-version branch; retain `AIProcessingServiceFactory` as the sole transport selection point.
- The App Intent must use `openAppWhenRun = false`. It can make an immediate best-effort attempt, but all background timing is system-controlled.
- Persist the screenshot image and record before scheduling or starting AI processing. A failed request keeps both.
- Do not auto-retry a completed failure. Recover only records stranded in `.processing` by process interruption; retain manual Retry for `.failed` and `.deadLetter`.
- Processing notifications must not depend on `UDK.notificationEnabled`, which controls calendar reminders.
- Add every visible literal to all three `Localizable.strings` files.
- Main-app sources need manual target membership in `Notiee.xcodeproj/project.pbxproj`; every new shared source goes into both app targets, every test only into `NotieeTests`.
- Preserve unrelated worktree changes. Do not commit unless separately authorized. Every authorized commit includes `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Prefix Xcode commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and build both targets with `iPhone 17` plus `CODE_SIGNING_ALLOWED=NO`.

---

## File Structure

**Create**

- `Notiee/Services/NotieeProcessingRuntime.swift`: singleton live store shared by app, App Intent, and BG task.
- `Notiee/Services/AIBackgroundTaskScheduler.swift`: BackgroundTasks registration/scheduling adapter.
- `Notiee/Services/ScreenshotImportService.swift`: validation, image persistence, record creation, schedule/start ordering.
- `Notiee/Features/Capture/NotieeScreenshotIntent.swift`: App Intent and `AppShortcutsProvider`.
- `NotieeTests/AIPipelineRecoveryTests.swift`: retry/recovery/notification tests.
- `NotieeTests/ScreenshotImportServiceTests.swift`: image-import tests.

**Modify**

- `Notiee/Models/AIProcessingState.swift`, `Notiee/Models/NoteRecord.swift`: notification-delivery state.
- `Notiee/Services/Managers/RecordManager.swift`, `Notiee/Services/NotieeStore.swift`, `Notiee/Services/Managers/AIPipelineManager.swift`: durable processing behavior.
- `Notiee/Services/NotificationManager.swift`, `Notiee/Services/SystemPermissionManager.swift`: terminal local notification and authorization.
- `Notiee/App/NotieeApp.swift`, `Notiee/App/RootTabView.swift`, both Info.plists, project file, and the three localization files.
- `HANDOFF.md`: actual execution evidence only after implementation.

### Task 1: Repair and Persist Processing State

**Files:**

- Modify: `Notiee/Models/AIProcessingState.swift`, `Notiee/Models/NoteRecord.swift`
- Modify: `Notiee/Services/Managers/RecordManager.swift`, `Notiee/Services/NotieeStore.swift`, `Notiee/Services/Managers/AIPipelineManager.swift`
- Create: `NotieeTests/AIPipelineRecoveryTests.swift`

**Consumes:** existing `AIProcessingService.process(imagePaths:eventTitle:)`.

**Produces:** `NotieeStore.resumePendingAIProcessing() async`, a repaired retry path, and persisted notification-delivery state.

- [ ] **Step 1: Write failing retry and interrupted-work tests**

Create this test shape, with a temporary `JSONNoteRecordStore`, `MockAIProcessingService(processingDelay: 0.01...0.02)`, and a 2-second polling `waitUntil` helper:

~~~swift
@MainActor
final class AIPipelineRecoveryTests: XCTestCase {
    func testRetryFailedRecord_reenqueuesAndCompletes() async throws {
        let record = NoteRecord(localImagePaths: ["retry"], processingState: .failed)
        let store = makeStore(records: [record])

        store.retryAIProcessing(for: record.id)
        try await waitUntil { store.record(id: record.id)?.processingState == .completed }

        XCTAssertEqual(store.record(id: record.id)?.processingState, .completed)
    }

    func testResumePendingAIProcessing_recoversInterruptedRecord() async throws {
        let record = NoteRecord(localImagePaths: ["interrupted"], processingState: .processing)
        let store = makeStore(records: [record])

        await store.resumePendingAIProcessing()

        XCTAssertEqual(store.record(id: record.id)?.processingState, .completed)
    }
}
~~~

- [ ] **Step 2: Run the red test**

Run:

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived -only-testing:NotieeTests/AIPipelineRecoveryTests CODE_SIGNING_ALLOWED=NO
~~~

Expected: Retry fails or times out because `NotieeStore.retryAIProcessing` changes the record to `.pending` before `retryAndEnqueue` rejects it; recovery API is absent.

- [ ] **Step 3: Add durable notification state**

Add to `AIProcessingState.swift`:

~~~swift
enum ProcessingNotificationState: String, Equatable, Hashable, Codable, Sendable {
    case none
    case requested
    case delivered
}
~~~

Add `processingNotificationState: ProcessingNotificationState` to `NoteRecord`, default `.none`, include it in `CodingKeys`, and use:

~~~swift
processingNotificationState = try c.decodeIfPresent(
    ProcessingNotificationState.self,
    forKey: .processingNotificationState
) ?? .none
~~~

No `RecordMigrator` version bump is needed because old JSON has a safe default.

Add these `RecordManager` operations and forward them through `AIPipelineRecordAccess` and the `NotieeStore` conformance:

~~~swift
func recordsNeedingAIRecovery() -> [NoteRecord] {
    records.filter {
        !$0.isDeleted && !$0.isEncrypted &&
        ($0.processingState == .pending || $0.processingState == .processing)
    }
}

func setProcessingNotificationState(
    _ state: ProcessingNotificationState,
    for recordID: UUID
) {
    guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
    records[index].processingNotificationState = state
    persistRecords()
}
~~~

- [ ] **Step 4: Replace the pipeline's fire-and-forget body with one async worker**

Add `private var inFlightRecordIDs = Set<UUID>()` to `AIPipelineManager`. Its public enqueue must start a task that awaits a single `process(recordID:localImagePaths:eventTitle:)` method; `process` must skip an ID already in flight, mark the record `.processing`, await the existing AI service, then apply the result or mark `.failed`, and remove the ID via `defer`.

Add:

~~~swift
func resumePendingProcessing() async {
    guard let access = recordAccess else { return }

    for record in access.recordsNeedingAIRecovery()
    where record.processingState == .processing {
        access.setProcessingState(.pending, for: record.id)
    }

    for record in access.recordsNeedingAIRecovery()
    where record.processingState == .pending {
        await process(
            recordID: record.id,
            localImagePaths: record.localImagePaths,
            eventTitle: access.eventTitle(for: record.id)
        )
    }
}
~~~

Extend `AIPipelineRecordAccess` with `recordsNeedingAIRecovery() -> [NoteRecord]` and `eventTitle(for recordID: UUID) -> String?`. Implement the latter in `NotieeStore` by resolving the record then delegating to its existing `eventTitle(for:)`.

Remove the unused `retryCount` parameter from the pipeline. It never increments `aiRetryCount` and must not imply an automatic-retry policy. Keep the existing `processRecord(_:)` AI-enabled guard for ordinary UI captures, but let `processImportedScreenshot(recordID:)` always call the worker. At the top of that worker, when `aiEnabled` is false, set the imported record to `.failed` and continue through the same terminal-notification path; this preserves the screenshot and gives the Shortcut user a definitive result.

Replace `NotieeStore.retryAIProcessing` with:

~~~swift
func retryAIProcessing(for recordID: UUID) {
    guard let record = recordManager.record(id: recordID),
          record.processingState == .failed || record.processingState == .deadLetter else { return }
    aiPipelineManager.enqueueProcessing(
        recordID: record.id,
        localImagePaths: record.localImagePaths,
        eventTitle: eventTitle(for: record)
    )
}

func resumePendingAIProcessing() async {
    await aiPipelineManager.resumePendingProcessing()
}
~~~

The pipeline, not the Store, changes a retrying record to `.processing`.

- [ ] **Step 5: Verify Task 1**

Run the Step 2 command, then:

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived -only-testing:NotieeTests/MockAIProcessingServiceTests CODE_SIGNING_ALLOWED=NO
~~~

Expected: both report `TEST SUCCEEDED`; a failed record retries and a persisted `.processing` record finishes after recovery.

- [ ] **Step 6: Commit only if authorized**

~~~bash
git add Notiee/Models/AIProcessingState.swift Notiee/Models/NoteRecord.swift Notiee/Services/Managers/RecordManager.swift Notiee/Services/NotieeStore.swift Notiee/Services/Managers/AIPipelineManager.swift NotieeTests/AIPipelineRecoveryTests.swift
git commit -m "fix(capture): recover pending AI processing" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
~~~

### Task 2: Send One Terminal Result Notification

**Files:**

- Modify: `Notiee/Services/NotificationManager.swift`, `Notiee/Services/SystemPermissionManager.swift`, `Notiee/Services/Managers/AIPipelineManager.swift`
- Modify: `Notiee/en.lproj/Localizable.strings`, `Notiee/zh-Hans.lproj/Localizable.strings`, `Notiee/zh-Hant.lproj/Localizable.strings`
- Modify: `NotieeTests/AIPipelineRecoveryTests.swift`

**Consumes:** Task 1's `ProcessingNotificationState`.

**Produces:** a permission-aware notification exactly once for records marked `.requested`.

- [ ] **Step 1: Write failing success/failure notifier tests**

Introduce this test seam:

~~~swift
protocol ProcessingResultNotifying: Sendable {
    func notify(recordID: UUID, outcome: AIProcessingState) async -> Bool
}
~~~

Inject a spy notifier into `AIPipelineManager`. In the recovery test file, create a record with `processingNotificationState: .requested`, process it with the mock service, and assert:

~~~swift
XCTAssertEqual(notifier.calls, [(record.id, .completed)])
XCTAssertEqual(
    store.record(id: record.id)?.processingNotificationState,
    .delivered
)
~~~

Repeat with a throwing test AI service. Assert `.failed`, identical `localImagePaths`, and one `.failed` notification.

- [ ] **Step 2: Run the red test**

Run the Task 1 focused test command. Expected: compilation fails until pipeline notification dependency exists.

- [ ] **Step 3: Implement the notifier**

Make `NotificationManager` conform to `ProcessingResultNotifying`. Check `UNUserNotificationCenter.current().notificationSettings()`. When authorization is denied, return `true` without adding a request; otherwise remove and add this immediate request:

~~~swift
let identifier = "notiee.ai-processing.\(recordID.uuidString)"
let content = UNMutableNotificationContent()
content.title = String(localized: outcome == .completed
    ? "截图已整理完成"
    : "截图已保存，但整理暂未完成")
content.body = String(localized: outcome == .completed
    ? "已生成拍记摘要。"
    : "原图和拍记已保留，可稍后重试。")
content.sound = .default
~~~

Return `true` only after `center.add` succeeds. After each terminal pipeline transition, read the record again; if its notification state remains `.requested`, call the notifier and persist `.delivered` only on `true`. This keeps recovery idempotent.

Add `requestNotifications()` to `SystemPermissionManager` by awaiting `NotificationManager.shared.requestPermission()`; invoke it after the existing photo-library request. Do not consult the calendar reminder preference.

Add these exact entries; append them near existing processing-status entries:

~~~text
// Notiee/en.lproj/Localizable.strings
"截图已整理完成" = "Screenshot organized";
"截图已保存，但整理暂未完成" = "Screenshot saved, but organization could not finish";
"已生成拍记摘要。" = "A note summary is ready.";
"原图和拍记已保留，可稍后重试。" = "The image and note were saved. You can retry later.";

// Notiee/zh-Hans.lproj/Localizable.strings
"截图已整理完成" = "截图已整理完成";
"截图已保存，但整理暂未完成" = "截图已保存，但整理暂未完成";
"已生成拍记摘要。" = "已生成拍记摘要。";
"原图和拍记已保留，可稍后重试。" = "原图和拍记已保留，可稍后重试。";

// Notiee/zh-Hant.lproj/Localizable.strings
"截图已整理完成" = "截圖已整理完成";
"截图已保存，但整理暂未完成" = "截圖已儲存，但整理暫未完成";
"已生成拍记摘要。" = "已產生拍記摘要。";
"原图和拍记已保留，可稍后重试。" = "原圖和拍記已保留，可稍後重試。";
~~~

- [ ] **Step 4: Verify Task 2**

Run the focused recovery test command. Expected: `TEST SUCCEEDED`; success/failure each schedule once, and a failure retains the image path.

- [ ] **Step 5: Commit only if authorized**

~~~bash
git add Notiee/Services/NotificationManager.swift Notiee/Services/SystemPermissionManager.swift Notiee/Services/Managers/AIPipelineManager.swift Notiee/en.lproj/Localizable.strings Notiee/zh-Hans.lproj/Localizable.strings Notiee/zh-Hant.lproj/Localizable.strings NotieeTests/AIPipelineRecoveryTests.swift
git commit -m "feat(capture): notify terminal AI processing" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
~~~

### Task 3: Register Background Recovery

**Files:**

- Create: `Notiee/Services/NotieeProcessingRuntime.swift`, `Notiee/Services/AIBackgroundTaskScheduler.swift`
- Modify: `Notiee/App/NotieeApp.swift`, `Notiee/App/RootTabView.swift`, `Notiee/Info.plist`, `Notiee copy-Info.plist`, `Notiee.xcodeproj/project.pbxproj`
- Modify: `NotieeTests/AIPipelineRecoveryTests.swift`

**Consumes:** `NotieeStore.resumePendingAIProcessing() async`.

**Produces:** one live store and a network-constrained BG task handler.

- [ ] **Step 1: Write a failing runtime test**

Create a `RecordingScheduler` fake and verify:

~~~swift
func testRuntimeSchedulesAndRunsPendingProcessing() async {
    let scheduler = RecordingScheduler()
    let store = makeStore(records: [NoteRecord(localImagePaths: ["pending"])])
    let runtime = NotieeProcessingRuntime(store: store, scheduler: scheduler)

    runtime.scheduleProcessing()
    await scheduler.runRegisteredHandler()

    XCTAssertEqual(scheduler.scheduleCallCount, 1)
    XCTAssertEqual(store.records.first?.processingState, .completed)
}
~~~

- [ ] **Step 2: Implement runtime and scheduler**

In `NotieeProcessingRuntime.swift`:

~~~swift
@MainActor
final class NotieeProcessingRuntime {
    static let shared = NotieeProcessingRuntime()
    let store: NotieeStore
    private let scheduler: any AIProcessingScheduling

    init(
        store: NotieeStore = .live(),
        scheduler: any AIProcessingScheduling = AIBackgroundTaskScheduler.shared
    ) {
        self.store = store
        self.scheduler = scheduler
    }

    func scheduleProcessing() { scheduler.scheduleProcessing() }
    func runPendingProcessing() async { await store.resumePendingAIProcessing() }
}
~~~

In `AIBackgroundTaskScheduler.swift`, create `AIProcessingScheduling` with `register(handler:)` and `scheduleProcessing()`. Production registration must occur once via `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)`. Its handler runs the supplied async closure, sets `taskCompleted(success: true)`, and cancels its child task from `expirationHandler`. Scheduling submits `BGProcessingTaskRequest(identifier: Self.identifier)`, sets `requiresNetworkConnectivity = true`, and treats a duplicate submission as already scheduled.

Use the exact identifier:

~~~swift
static let identifier = "com.idbetterrun.notiee.ai-processing"
~~~

In `AppDelegate.application(_:didFinishLaunchingWithOptions:)`:

~~~swift
AIBackgroundTaskScheduler.shared.register {
    await NotieeProcessingRuntime.shared.runPendingProcessing()
}
Task { @MainActor in
    await NotieeProcessingRuntime.shared.runPendingProcessing()
}
~~~

Change RootTabView's default store construction from `NotieeStore.live(...)` to `NotieeProcessingRuntime.shared.store`, keeping its injectable initializer untouched.

- [ ] **Step 3: Declare the task in both products**

Add to both `Notiee/Info.plist` and `Notiee copy-Info.plist`:

~~~xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.idbetterrun.notiee.ai-processing</string>
</array>
<key>UIBackgroundModes</key>
<array>
    <string>processing</string>
</array>
~~~

Add the two services to the Services group and Sources phases of both app targets; add `AIPipelineRecoveryTests.swift` only to the test target. Use unique 24-character PBX IDs.

- [ ] **Step 4: Verify Task 3**

Run:

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived -only-testing:NotieeTests/AIPipelineRecoveryTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Notiee.xcodeproj -scheme Notiee+ -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived CODE_SIGNING_ALLOWED=NO
~~~

Expected: test and both builds succeed.

- [ ] **Step 5: Commit only if authorized**

~~~bash
git add Notiee/Services/NotieeProcessingRuntime.swift Notiee/Services/AIBackgroundTaskScheduler.swift Notiee/App/NotieeApp.swift Notiee/App/RootTabView.swift Notiee/Info.plist "Notiee copy-Info.plist" Notiee.xcodeproj/project.pbxproj NotieeTests/AIPipelineRecoveryTests.swift
git commit -m "feat(capture): resume AI work in background" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
~~~

### Task 4: Import Screenshot Variables Through App Intents

**Files:**

- Create: `Notiee/Services/ScreenshotImportService.swift`, `Notiee/Features/Capture/NotieeScreenshotIntent.swift`, `NotieeTests/ScreenshotImportServiceTests.swift`
- Modify: `Notiee/Services/LocalImageStore.swift`, `Notiee/Services/NotieeStore.swift`, all three localization files, `Notiee.xcodeproj/project.pbxproj`

**Consumes:** Tasks 1-3's worker, runtime, notification state, and scheduler.

**Produces:** `Save Screenshot to Notiee` in the Shortcuts action list with an image input.

- [ ] **Step 1: Write failing importer tests**

Use a spy saver and scheduler:

~~~swift
func testImport_validImageSavesRecordBeforeScheduling() throws {
    let store = makeStore(records: [])
    let saver = SpyImageSaver(path: "CapturedImages/shortcut.jpg")
    let scheduler = RecordingScheduler()
    let service = ScreenshotImportService(store: store, imageSaver: saver, scheduler: scheduler)

    let recordID = try service.importScreenshotData(makePNGData())

    XCTAssertEqual(saver.saveCallCount, 1)
    XCTAssertEqual(store.record(id: recordID)?.localImagePaths, ["CapturedImages/shortcut.jpg"])
    XCTAssertEqual(store.record(id: recordID)?.processingState, .pending)
    XCTAssertEqual(store.record(id: recordID)?.processingNotificationState, .requested)
    XCTAssertEqual(scheduler.scheduleCallCount, 1)
}

func testImport_invalidDataThrowsWithoutCreatingRecord() {
    let store = makeStore(records: [])
    let service = ScreenshotImportService(store: store, imageSaver: SpyImageSaver(path: "unused"), scheduler: RecordingScheduler())

    XCTAssertThrowsError(try service.importScreenshotData(Data("not an image".utf8)))
    XCTAssertTrue(store.records.isEmpty)
}
~~~

- [ ] **Step 2: Run the red test**

Run:

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived -only-testing:NotieeTests/ScreenshotImportServiceTests CODE_SIGNING_ALLOWED=NO
~~~

Expected: compilation fails because the importer and injected image-saving seam do not exist.

- [ ] **Step 3: Implement persist-before-schedule import**

Add this focused seam to `LocalImageStore.swift`:

~~~swift
@MainActor
protocol ImageSaving {
    func saveImage(_ image: UIImage) throws -> String
}
extension LocalImageStore: ImageSaving {}
~~~

Create the error before the service:

~~~swift
enum ScreenshotImportError: LocalizedError {
    case missingImage
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .missingImage: String(localized: "未提供截图")
        case .invalidImage: String(localized: "截图格式无效")
        }
    }
}
~~~

Create:

~~~swift
@MainActor
struct ScreenshotImportService {
    let store: NotieeStore
    let imageSaver: any ImageSaving
    let scheduler: any AIProcessingScheduling

    func importScreenshotData(_ data: Data) throws -> UUID {
        guard let image = UIImage(data: data) else {
            throw ScreenshotImportError.invalidImage
        }
        let imagePath = try imageSaver.saveImage(image)
        let record = store.captureShortcutScreenshot(localImagePath: imagePath)
        scheduler.scheduleProcessing()
        store.processImportedScreenshot(recordID: record.id)
        return record.id
    }
}
~~~

`captureShortcutScreenshot` must follow the existing event-resolution and record-manager capture path, mark the new record `.requested`, persist it, then return it. `processImportedScreenshot` must enqueue whenever `aiEnabled` is true, ignoring `autoProcessAfterCapture`; when AI is disabled, mark the new record `.failed` and send its terminal notification so the user knows the screenshot still exists.

- [ ] **Step 4: Register the action**

Create `NotieeScreenshotIntent.swift`:

~~~swift
import AppIntents
import UniformTypeIdentifiers

@available(iOS 18.0, *)
struct NotieeScreenshotIntent: AppIntent {
    #if NOTIEE_PLUS
    static var title: LocalizedStringResource = "保存截图到 Notiee+"
    #else
    static var title: LocalizedStringResource = "保存截图到 Notiee"
    #endif
    static var description = IntentDescription("将截图保存为拍记并在后台整理")
    static var openAppWhenRun = false

    @Parameter(
        title: "截图",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let screenshot else { throw ScreenshotImportError.missingImage }
        _ = try ScreenshotImportService(
            store: NotieeProcessingRuntime.shared.store,
            imageSaver: LocalImageStore.shared,
            scheduler: AIBackgroundTaskScheduler.shared
        ).importScreenshotData(screenshot.data)
        return .result(dialog: "截图已保存，正在后台整理")
    }
}

@available(iOS 18.0, *)
struct NotieeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [AppShortcut(
            intent: NotieeScreenshotIntent(),
            phrases: ["保存截图到 \(.applicationName)"],
            shortTitle: "保存截图",
            systemImageName: "camera.viewfinder"
        )]
    }
}
~~~

Keep `NotieeCameraIntent` unchanged. `inputConnectionBehavior: .connectToPreviousIntentResult` is required: it causes a Shortcut containing `Take Screenshot` immediately before this action to auto-bind the screenshot variable, rather than prompting the user to choose from Photos. Add production files to both app Sources phases and the importer test to the test target.

Add these exact entries, with equivalent Traditional Chinese values in `zh-Hant`:

~~~text
"保存截图到 Notiee" = "Save Screenshot to Notiee";
"保存截图到 Notiee+" = "Save Screenshot to Notiee+";
"将截图保存为拍记并在后台整理" = "Save a screenshot as a note and organize it in the background";
"截图" = "Screenshot";
"截图已保存，正在后台整理" = "Screenshot saved. Organizing it in the background.";
"保存截图" = "Save Screenshot";
"未提供截图" = "No screenshot was provided.";
"截图格式无效" = "The screenshot format is invalid.";
~~~

- [ ] **Step 5: Verify Task 4**

Run:

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived -only-testing:NotieeTests/ScreenshotImportServiceTests CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Notiee.xcodeproj -scheme Notiee+ -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived CODE_SIGNING_ALLOWED=NO
~~~

Expected: all commands succeed; on device, Shortcuts exposes one image field named Screenshot.

- [ ] **Step 6: Device acceptance and handoff**

On an iPhone, create:

1. `Take Screenshot`
2. `Save Screenshot to Notiee`, setting the Screenshot parameter to the preceding Screenshot magic variable.

Run it while Notiee is not foregrounded. Verify the image thumbnail and record exist, then exactly one terminal success notification. Repeat with unavailable network or an invalid Plus model configuration; verify the image remains, the record is `.failed`, one failure notification appears, and detail Retry starts processing.

Append actual results to `HANDOFF.md` in English, including the background identifier and the fact that iOS scheduling is best-effort.

- [ ] **Step 7: Commit only if authorized**

~~~bash
git add Notiee/Services/ScreenshotImportService.swift Notiee/Services/LocalImageStore.swift Notiee/Services/NotieeStore.swift Notiee/Features/Capture/NotieeScreenshotIntent.swift Notiee/en.lproj/Localizable.strings Notiee/zh-Hans.lproj/Localizable.strings Notiee/zh-Hant.lproj/Localizable.strings Notiee.xcodeproj/project.pbxproj NotieeTests/ScreenshotImportServiceTests.swift HANDOFF.md
git commit -m "feat(shortcuts): import screenshots into background capture" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
~~~

### Task 5: Final Regression Verification

**Files:**

- Modify: `HANDOFF.md`

- [ ] **Step 1: Run focused tests**

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-derived -only-testing:NotieeTests/MockAIProcessingServiceTests -only-testing:NotieeTests/AIPipelineRecoveryTests -only-testing:NotieeTests/ScreenshotImportServiceTests CODE_SIGNING_ALLOWED=NO
~~~

Expected: `TEST SUCCEEDED`, covering valid/invalid import, persistence before scheduling, retained images, manual retry, interrupted recovery, and single notification delivery.

- [ ] **Step 2: Build both products from clean derived data**

~~~bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-final-derived CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Notiee.xcodeproj -scheme Notiee+ -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/notiee-shortcut-final-derived CODE_SIGNING_ALLOWED=NO
~~~

Expected: both report `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit only if authorized**

~~~bash
git add HANDOFF.md
git commit -m "test(capture): verify screenshot shortcut pipeline" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
~~~
