# iOS MVP Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first Notiee iOS foundation: a SwiftUI app shell, four-tab navigation, core domain models, and schedule matching tests.

**Architecture:** Keep the first step local and native. The app target owns SwiftUI feature shells and lightweight domain models; persistence, camera capture, and AI processing are left as follow-up implementation tasks.

**Tech Stack:** SwiftUI, XCTest, Xcode project, iOS 17+.

---

### Task 1: Project And Navigation Shell

**Files:**
- Create: `Notiee.xcodeproj/project.pbxproj`
- Create: `Notiee.xcodeproj/xcshareddata/xcschemes/Notiee.xcscheme`
- Create: `Notiee/App/NotieeApp.swift`
- Create: `Notiee/App/RootTabView.swift`
- Create: `Notiee/Features/Today/TodayView.swift`
- Create: `Notiee/Features/Capture/CaptureView.swift`
- Create: `Notiee/Features/Records/RecordsView.swift`
- Create: `Notiee/Features/Settings/SettingsView.swift`

- [x] **Step 1: Create a minimal Xcode project**

Set up an iOS app target named `Notiee` and a unit test target named `NotieeTests`.

- [x] **Step 2: Create the four-tab SwiftUI shell**

Use a native `TabView` with `Today`, `拍记`, `记录`, and `我`.

### Task 2: Core Domain Models And Schedule Matching

**Files:**
- Create: `Notiee/Models/ScheduledEvent.swift`
- Create: `Notiee/Models/NoteRecord.swift`
- Create: `Notiee/Models/NoteTodo.swift`
- Create: `Notiee/Models/AIProcessingState.swift`
- Create: `Notiee/Services/ScheduleMatcher.swift`
- Create: `NotieeTests/ScheduleMatcherTests.swift`

- [x] **Step 1: Write failing schedule matching tests**

Test no match, normal in-range matching, and overlap resolution.

- [x] **Step 2: Implement the minimal matcher**

Add `ScheduleMatcher.currentEvent(from:at:)`.

- [x] **Step 3: Run unit tests and app build**

Run `xcodebuild test` for the simulator and `xcodebuild build` for the app target.
