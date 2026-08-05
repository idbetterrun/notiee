# Today 2.0 Context Dashboard - Design Specification

| Field | Value |
| --- | --- |
| Date | 2026-07-29 |
| Scope | Shared Notiee and Notiee+ UI/domain behavior |
| Status | Approved product direction; implementation not started |

## Goal

Replace the current scrollable Today timeline with a fixed-screen Context Dashboard. It answers one question within the first second: what matters most right now?

Today is not a todo list, timeline, or feed. Existing data remains available through Records, event and todo details, and Spark; Today deliberately displays a bounded subset.

## Fixed Screen and Context Rules

- The page content never vertically scrolls.
- The header, exactly one Hero Card, at most two urgent items, one adaptive review slot, and optional statistics fit the available safe-area height.
- When height is constrained, statistics disappear first. The Hero Card is never hidden.
- Controls own their own gestures. Root capture gestures do not start while Spark, a sheet, a navigation transition, the keyboard, or a detail control is active.

Hero selection is deterministic and local. Spark may later provide concise supporting copy, but it does not choose what is important: a network request cannot make Today late, blank, or unpredictable.

The phase-one priority order is:

1. An active scheduled event. This is the proxy for an active focus context because the app has no focus-session model.
2. An incomplete todo due within two hours, including overdue todos.
3. A scheduled event starting within the next 30 minutes.
4. Three or more records captured today.
5. A calm invitation to record.

The resolver also returns bounded supporting data:

- Up to two overdue/due-soon todos or imminent events that are not already the Hero.
- An execution Hero shows up to three actionable todos; a reflection/calm Hero shows up to three latest records from today.
- A compact record/todo count is optional and is removed first under height pressure.

## Navigation and Spark

The root becomes a custom shell, not `TabView`:

```text
Today | central persistent Spark composer | Records
```

- Today and Records are the only navigable destinations.
- Capture is an action, not a tab. Today and hardware Camera Control route to the same camera presentation.
- Central Spark opens a bottom-origin full-screen composer, focuses input after presentation, and opens the keyboard.
- `RootTabView` owns one `SparkViewModel`; closing the composer must retain the draft, chat, loading state, agent state, privacy gate, and model configuration.
- Spark transport remains isolated by the existing compile-time target design: Notiee uses its backend path and Notiee+ uses BYOK. The new shared UI adds no runtime version branching.
- Old persisted default-tab values `capture` and `spark` are migrated to `today`; Settings offers only Today and Records as launch destinations.

## Today Capture Gestures

### Downward pull: camera

1. A 18 pt downward pull prepares the authorized camera session: permission and inputs/outputs only, no running sensor.
2. At 88 pt, start the sensor, show a camera affordance, and give exactly one light haptic.
3. Releasing while armed opens camera. Pulling back below the threshold cancels. A prepared but unused session releases after a 750 ms grace period.

This balances camera startup time with the privacy indicator: accidental short pulls do not start the camera. Denied/restricted permissions use the existing camera permission path.

### Upward push: audio entry

The upward gesture uses the same threshold, haptic, and release pattern but opens an audio-entry surface only. This release does not record, store audio, request microphone permission, or transcribe.

## Feature Preservation and Non-goals

- Preserve account/settings access, todo toggling/details, event details, record details, manual creation, TMN import, hardware Camera Control, camera processing, and Spark history/privacy/Agent functionality.
- Add every visible string to English, Simplified Chinese, and Traditional Chinese catalogs.
- All shared source files are registered in both application targets; tests are registered in `NotieeTests`.

Not in this release: focus-session storage, AI Hero selection, an unlimited Today list, actual audio recording/transcription, free-backend changes, or Notiee+ vendor-transport changes.

## Verification

Unit tests cover priority/caps, launch migration, pull transitions, haptic single-fire behavior, and prepare-versus-start camera behavior. Build both app schemes. Physical iOS 26 testing is required for gesture competition, camera privacy timing, haptic feel, first-frame latency, keyboard focus, full-screen Spark transition, and small-screen clipping.
