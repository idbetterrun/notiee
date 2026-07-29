# Screenshot Shortcut Background Processing Design

| Field | Value |
| --- | --- |
| Date | 2026-07-23 |
| Scope | Shared capture and processing flow: Notiee and Notiee+ |
| Status | Approved for implementation planning |

## Problem

Notiee can launch its camera from Shortcuts, but cannot accept the image emitted by the system `Take Screenshot` action. Its AI pipeline starts an in-memory task only, so interrupted work has no background recovery path. The current manual retry also changes a record to `pending` before calling a method that only accepts `failed` or `deadLetter`.

The required flow is:

`Take Screenshot` -> `Save Screenshot to Notiee` -> durable local record -> background AI processing -> terminal local notification.

The user never needs to open Notiee to submit or wait for the screenshot. An AI failure must never delete the image or its record.

## Goals

- Register an App Intent named `Save Screenshot to Notiee` that accepts an image variable and uses `openAppWhenRun = false`.
- Persist the image and a `pending` photo record before an AI request begins.
- Resume work interrupted while suspended or killed through `BGProcessingTask` and persisted-record recovery at launch.
- Notify once when a Shortcut-originated record reaches `completed` or `failed`.
- Retain the image, record, and existing manual Retry path on every failure.
- Retain the existing AI service factory boundary: free uses the self-hosted backend; Plus uses BYOK.

## Non-Goals

- Do not observe arbitrary device screenshots. iOS only supplies a screenshot that a user deliberately passes through a Shortcut.
- Do not add server-side jobs, push notifications, cloud sync, a second queue database, or automatic retry after a completed AI request fails.
- Do not change navigation, Capture UI, Spark, quotas, or the existing camera App Intent.
- Do not promise a wall-clock completion time. iOS schedules `BGProcessingTask` opportunistically; the app starts work immediately when possible and resumes later.

## Design

### Durable Queue

`NoteRecord` remains the sole persisted queue. Add Codable `processingNotificationState` with `none`, `requested`, and `delivered`. The screenshot importer creates a `.photo`, `.pending` record with `.requested`; missing values in old JSON decode as `.none`.

`AIPipelineManager` owns terminal transitions. It applies the AI result then schedules a success notification, or changes only the processing state to `.failed` and schedules a failure notification. In both cases the image path remains unchanged. The stable notification identifier is `notiee.ai-processing.<record UUID>`, so recovery replaces rather than duplicates a request.

There is no automatic retry after an AI service error. A `.processing` record is returned to `.pending` only when a fresh recovery pass proves that its prior process was interrupted. The detail view Retry button is repaired to enqueue a failed/dead-letter record through the same worker.

### Background Runtime

`NotieeProcessingRuntime` owns exactly one live `NotieeStore` for the process. RootTabView, the App Intent, and the BG-task handler share it, preventing two in-memory managers from mutating the same records JSON file.

`AIBackgroundTaskScheduler` registers `com.idbetterrun.notiee.ai-processing` when the app launches. The screenshot importer requests a network-constrained processing task after durable import. The task and ordinary app launch both call the same pipeline recovery/drain method. Expiration cancels in-flight execution; the persisted record remains recoverable.

Both app Info.plists declare the task identifier in `BGTaskSchedulerPermittedIdentifiers` and add `processing` to `UIBackgroundModes`.

### Shortcut Registration

A new iOS 18 `AppIntent` has an optional `IntentFile` parameter restricted to `UTType.image`, `openAppWhenRun = false`, and `inputConnectionBehavior: .connectToPreviousIntentResult`. The connection behavior tells Shortcuts to bind the preceding `Take Screenshot` result automatically rather than opening the image picker. It validates `IntentFile.data`, writes a decoded `UIImage` through `LocalImageStore`, creates the record, then schedules and starts processing. Invalid image data fails in Shortcuts before a record is made.

`AppShortcutsProvider` exposes the action and a Siri phrase. The user configures:

1. `Take Screenshot`
2. `Save Screenshot to Notiee`, binding its Screenshot field to the preceding Screenshot magic variable.

### Notifications

Processing notifications do not consult `UDK.notificationEnabled`, which remains the calendar-reminder preference. The onboarding permission manager requests notification authorization alongside existing system permissions. If denied, processing and record persistence still complete; the notification state is marked delivered to avoid repeated work.

Success: `Screenshot organized`. Failure: `Screenshot saved, but organization could not finish`. A failure means the saved record is visible as failed and can be retried manually.

## Error Handling

| Situation | Stored outcome | Notification | Recovery |
| --- | --- | --- | --- |
| Invalid shortcut input | No record | Shortcuts error | Correct input |
| AI succeeds | `completed` + result | Success once | None |
| AI/network/config/quota fails | `failed`, image retained | Failure once | Detail Retry |
| Process interrupted | Record retained; `processing` reset to `pending` | None until terminal | Launch or BG task |
| Notification denied | Terminal state unchanged | None | No repeated attempt |

## Verification

- Unit tests cover valid/invalid image import, persist-before-schedule order, retained image after failure, repaired manual retry, interrupted-work recovery, and one terminal notification.
- Build both Notiee and Notiee+ after every shared-source task.
- On a physical iPhone, create the two-action Shortcut, run it while Notiee is not foregrounded, verify the resulting record and terminal notification, then verify a failure retains its image. Background scheduling timing itself is not deterministic.
