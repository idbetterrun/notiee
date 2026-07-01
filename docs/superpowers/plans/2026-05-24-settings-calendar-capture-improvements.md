# Settings Calendar & Capture Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Capture eventID bug, restructure Capture menu, add calendar selection in Settings, show holidays/birthdays on Today, restore Backup & Restore entry, move iCloud sync to Lab Features.

**Architecture:** All changes stay within existing MVVM + @MainActor singleton pattern. Settings gain a new "日程" section powered by `CalendarService` exposing available calendars. Today page gains a holiday/birthday banner between date header and timeline. CaptureViewModel properly passes `selectedEventID` to `NotieeStore`. Menu deduplicates events by title.

**Tech Stack:** SwiftUI, EventKit, Combine, UserDefaults (via `AppSettingsPersisting`)

---

## Task 1: Add restart note under "第一周开始日期" in Settings

**Files:**
- Modify: `Notiee/Features/Settings/SettingsView.swift` (around lines 274-276)

- [ ] **Step 1: Add the footnote text**

In `SettingsMainView`, find the `Section("常规")` block. After the closing `}` of the `if viewModel.showWeekNumbers { ... }` (line 275), add the restart note inside the section:

```swift
Section("常规") {
    Picker("App 启动页", selection: $viewModel.defaultTab) {
        Text(AppTab.today.titleKey).tag(AppTab.today)
        Text(AppTab.capture.titleKey).tag(AppTab.capture)
        Text(AppTab.records.titleKey).tag(AppTab.records)
    }
    .onChange(of: viewModel.defaultTab) { _, _ in viewModel.saveDefaultTab() }
    
    Toggle("显示周数", isOn: $viewModel.showWeekNumbers)
    if viewModel.showWeekNumbers {
        let dateBinding = Binding<Date>(
            get: { viewModel.semesterStartDate ?? Date() },
            set: { viewModel.semesterStartDate = $0 }
        )
        DatePicker("第一周开始日期", selection: dateBinding, displayedComponents: .date)
    }
}
```

Find line 275-276 (the closing of the section):
```swift
        }
    }
    .onChange(of: viewModel.showWeekNumbers) { _, _ in viewModel.saveAll() }
    .onChange(of: viewModel.semesterStartDate) { _, _ in viewModel.saveAll() }
```

Replace with — add the note text after the `DatePicker` line, before the closing `}`:

```swift
        }
        if viewModel.showWeekNumbers {
            Text("修改第一周开始日期后需要重新启动应用才能生效")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    .onChange(of: viewModel.showWeekNumbers) { _, _ in viewModel.saveAll() }
    .onChange(of: viewModel.semesterStartDate) { _, _ in viewModel.saveAll() }
```

- [ ] **Step 2: Verify build compiles**

Run: `xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Notiee/Features/Settings/SettingsView.swift
git commit -m "feat: add restart note under first week start date in Settings"
```

---

## Task 2: Add "日程" calendar selection section in Settings

**Files:**
- Modify: `Notiee/Services/CalendarService.swift` — add calendar enumeration and filtering
- Modify: `Notiee/Features/Settings/SettingsViewModel.swift` — add `availableCalendars`, `selectedCalendarIDs`
- Modify: `Notiee/Features/Settings/SettingsView.swift` — insert "日程" section between "常规" and "外观"

### 2a: Extend CalendarService to enumerate and filter calendars

- [ ] **Step 1: Add calendar listing and filtering to CalendarService.swift**

Add a published property for available calendars and a method to select them:

In `CalendarService.swift`, add import and properties:

```swift
import Foundation
import EventKit

@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()
    
    private let eventStore = EKEventStore()
    
    @Published private(set) var isAuthorized = false
    @Published private(set) var availableCalendars: [EKCalendar] = []
    
    private init() {
        checkAuthorizationStatus()
    }
    
    private func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            isAuthorized = (status == .fullAccess || status == .writeOnly)
        } else {
            isAuthorized = (status == .authorized)
        }
        if isAuthorized {
            reloadCalendars()
        }
    }
    
    func reloadCalendars() {
        availableCalendars = eventStore.calendars(for: .event)
            .sorted { ($0.title) < ($1.title) }
    }
    
    func selectedCalendarIDs() -> Set<String> {
        if let data = UserDefaults.standard.data(forKey: "notiee.selectedCalendarIdentifiers"),
           let ids = try? JSONDecoder().decode(Set<String>.self, from: data) {
            return ids
        }
        return Set(availableCalendars.map { $0.calendarIdentifier })
    }
    
    func saveSelectedCalendarIDs(_ ids: Set<String>) {
        let data = try? JSONEncoder().encode(ids)
        UserDefaults.standard.set(data, forKey: "notiee.selectedCalendarIdentifiers")
    }
```

Then modify `fetchEvents` to use `selectedCalendarIDs()` instead of `calendars: nil`:

In `fetchEvents`, change:
```swift
let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
let ekEvents = eventStore.events(matching: predicate)
```

To:
```swift
let allowedIDs = selectedCalendarIDs()
let filteredCalendars = allowedIDs.isEmpty ? nil : eventStore.calendars(for: .event).filter { allowedIDs.contains($0.calendarIdentifier) }
let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: filteredCalendars)
let ekEvents = eventStore.events(matching: predicate)
```

And in `requestAccess`, after authorization is granted, call `reloadCalendars()`:

```swift
func requestAccess() async -> Bool {
    do {
        var granted = false
        if #available(iOS 17.0, *) {
            granted = try await eventStore.requestFullAccessToEvents()
        } else {
            granted = try await eventStore.requestAccess(to: .event)
        }
        isAuthorized = granted
        if granted {
            reloadCalendars()
        }
        return granted
    } catch {
        print("Failed to request calendar access: \(error)")
        return false
    }
}
```

- [ ] **Step 2: Verify CalendarService changes compile**

Run: `xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20`

---

### 2b: Add calendar selection properties to SettingsViewModel

- [ ] **Step 3: Add the calendar properties to SettingsViewModel.swift**

Add `@Published` properties inside the `SettingsViewModel` class (after existing properties):

```swift
@Published var availableCalendars: [EKCalendar] = []
@Published var selectedCalendarIDs: Set<String> = []
```

Import EventKit at the top of SettingsViewModel.swift:

```swift
import Combine
import Foundation
import EventKit
import SwiftUI
```

(Check existing imports first; add `import EventKit` if not present.)

Add a method to load and save calendar selection:

```swift
func loadCalendarSelection() {
    availableCalendars = CalendarService.shared.availableCalendars
    selectedCalendarIDs = CalendarService.shared.selectedCalendarIDs()
}

func toggleCalendar(_ id: String) {
    if selectedCalendarIDs.contains(id) {
        selectedCalendarIDs.remove(id)
    } else {
        selectedCalendarIDs.insert(id)
    }
    CalendarService.shared.saveSelectedCalendarIDs(selectedCalendarIDs)
}
```

- [ ] **Step 4: Create CalendarSelectionView inside SettingsView.swift**

Add a new view at the end of `SettingsView.swift` (before the last closing `}` of any existing struct, or at the file end):

```swift
// MARK: - Calendar Selection

struct CalendarSelectionView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                        .padding(.top, 8)
                    
                    Text("日程读取设置")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            Section {
                if viewModel.availableCalendars.isEmpty {
                    Text("未找到可用的系统日历，请先在系统设置中授权访问。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.availableCalendars, id: \.calendarIdentifier) { calendar in
                        Button {
                            viewModel.toggleCalendar(calendar.calendarIdentifier)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(cgColor: calendar.cgColor))
                                    .frame(width: 12, height: 12)
                                Text(calendar.title)
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.selectedCalendarIDs.contains(calendar.calendarIdentifier) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("取消勾选某个日历后，Notiee 将不再读取该日历中的日程。系统日历（如节假日、生日等）默认显示在 Today 页面。")
            }
        }
        .navigationTitle("日程")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.loadCalendarSelection()
        }
    }
}
```

- [ ] **Step 5: Insert "日程" section in SettingsMainView**

In `SettingsMainView` body, between `Section("常规")` and `Section("外观")`, add:

```swift
Section("日程") {
    NavigationLink {
        CalendarSelectionView(viewModel: viewModel)
    } label: {
        Label("系统日历选择", systemImage: "calendar")
    }
}
```

The order should be:
1. Section("常规") — existing
2. **Section("日程") — NEW**
3. Section("外观") — existing
4. ...

- [ ] **Step 6: Verify build**

Run: `xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Notiee/Services/CalendarService.swift Notiee/Features/Settings/SettingsViewModel.swift Notiee/Features/Settings/SettingsView.swift
git commit -m "feat: add calendar selection section in Settings with system calendar filtering"
```

---

## Task 3: Show holidays and birthdays on Today page

**Files:**
- Modify: `Notiee/Services/CalendarService.swift` — add helper to detect holiday/birthday for a given date
- Modify: `Notiee/Features/Today/TodayView.swift` — add holiday/birthday banner between date header and timeline

- [ ] **Step 1: Add holiday/birthday detection to CalendarService**

Add this method to `CalendarService`:

```swift
func holidayOrBirthdayText(for date: Date) -> String? {
    guard isAuthorized else { return nil }
    
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
    
    // Filter calendars by selected IDs, or use all if none selected
    let allowedIDs = selectedCalendarIDs()
    let filteredCalendars = allowedIDs.isEmpty
        ? eventStore.calendars(for: .event)
        : eventStore.calendars(for: .event).filter { allowedIDs.contains($0.calendarIdentifier) }
    
    let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: filteredCalendars)
    let events = eventStore.events(matching: predicate)
    
    for ekEvent in events {
        // Check for birthday calendar type
        if ekEvent.calendar?.type == .birthday {
            if let title = ekEvent.title {
                // EKCalendarType.birthday events have titles like "张三的生日"
                return title
            }
        }
        
        // Check for holiday-related keywords in calendar title
        let calTitle = ekEvent.calendar?.title ?? ""
        if calTitle.contains("节") || calTitle.contains("假日") || calTitle.contains("Holiday") || calTitle.contains("节日") {
            if let title = ekEvent.title {
                // All-day events are typically holidays
                return title
            }
        }
        
        // Check if the event title contains "生日" or "birthday"
        let eventTitle = ekEvent.title ?? ""
        if eventTitle.contains("生日") || eventTitle.localizedCaseInsensitiveContains("birthday") {
            return eventTitle
        }
        
        // Check for keywords in event title like 节
        if eventTitle.contains("节") && eventTitle.count < 20 {
            return eventTitle
        }
    }
    
    return nil
}
```

- [ ] **Step 2: Add holiday/birthday display to TodayView**

In `TodayView.swift`, in the `header` computed property, add a subtext between the date text and the closing of the `VStack` for the header. Replace the current `header`:

Find the `header` var which currently spans lines with:
```swift
private var header: some View {
    HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                ...
            Text(viewModel.formattedDateWithWeek)
                ...
        }
        Spacer()
        Button { ... } label: { ... }
    }
}
```

Modify to add an `@State private var holidayText: String?` at the top of `TodayView` struct, and update the header to show it:

First, add a state property at the top of `TodayView`:
```swift
@State private var holidayText: String? = nil
```

Then modify the header VStack:
```swift
private var header: some View {
    HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(viewModel.formattedDateWithWeek)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if let holiday = holidayText {
                Text(holiday)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }

        Spacer()

        Button {
            showCreateSheet = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.blue)
        }
    }
    .onAppear {
        holidayText = CalendarService.shared.holidayOrBirthdayText(for: viewModel.currentDate)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Notiee/Services/CalendarService.swift Notiee/Features/Today/TodayView.swift
git commit -m "feat: show holidays and birthdays on Today page between date and timeline"
```

---

## Task 4: Fix Capture bug — eventID not saved on second selection

**Root cause:** `CaptureViewModel.handleCapturedImage` and `finishBatch` call `store.capturePhoto(localImagePaths:)` which uses `NotieeStore.currentEvent` (always auto-match), ignoring `CaptureViewModel.selectedEventID`.

**Files:**
- Modify: `Notiee/Services/NotieeStore.swift` — add `eventID` parameter to `capturePhoto`
- Modify: `Notiee/Features/Capture/CaptureViewModel.swift` — pass `currentEvent?.id` to `store.capturePhoto`

- [ ] **Step 1: Add eventID parameter to NotieeStore.capturePhoto**

In `NotieeStore.swift`, change:
```swift
@discardableResult
func capturePhoto(localImagePaths: [String]? = nil) -> NoteRecord {
    let record = NoteRecord(
        eventID: currentEvent?.id,
        capturedAt: currentDate,
        localImagePaths: localImagePaths ?? [],
        title: currentEvent.map { "\($0.title) 拍记" } ?? "未分类拍记",
        processingState: .pending
    )
```

To:
```swift
@discardableResult
func capturePhoto(localImagePaths: [String]? = nil, eventID: UUID? = nil) -> NoteRecord {
    let resolvedEventID = eventID ?? currentEvent?.id
    let resolvedEventTitle: String? = {
        if let id = resolvedEventID {
            return events.first(where: { $0.id == id })?.title
        }
        return currentEvent?.title
    }()
    
    let record = NoteRecord(
        eventID: resolvedEventID,
        capturedAt: currentDate,
        localImagePaths: localImagePaths ?? [],
        title: resolvedEventTitle.map { "\($0) 拍记" } ?? "未分类拍记",
        processingState: .pending
    )
```

- [ ] **Step 2: Pass currentEvent?.id from CaptureViewModel**

In `CaptureViewModel.swift`, change the `handleCapturedImage` method. Find:
```swift
if let store {
    let record = store.capturePhoto(localImagePaths: [relativePath])
    if !store.autoProcessAfterCapture {
        store.processRecord(record)
    }
}
```

Change to:
```swift
if let store {
    let record = store.capturePhoto(localImagePaths: [relativePath], eventID: currentEvent?.id)
    if !store.autoProcessAfterCapture {
        store.processRecord(record)
    }
}
```

In `finishBatch`, find:
```swift
if let store {
    let record = store.capturePhoto(localImagePaths: batchImagePaths)
    if !store.autoProcessAfterCapture {
        store.processRecord(record)
    }
}
```

Change to:
```swift
if let store {
    let record = store.capturePhoto(localImagePaths: batchImagePaths, eventID: currentEvent?.id)
    if !store.autoProcessAfterCapture {
        store.processRecord(record)
    }
}
```

- [ ] **Step 3: Verify build and run tests**

Run build:
```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED

Run tests:
```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test 2>&1 | grep -E "(Test Suite|passed|failed)"
```
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Notiee/Services/NotieeStore.swift Notiee/Features/Capture/CaptureViewModel.swift
git commit -m "fix: pass selectedEventID to store.capturePhoto so records save to chosen folder"
```

---

## Task 5: Restructure Capture schedule path selection menu

**Requirements:**
1. Active schedule pinned first (if any)
2. "未分类" second (always present)
3. Divider below
4. Remaining schedules, **deduplicated by title**
5. Selected item shows checkmark
6. If no active schedule, "未分类" is first, no pinned active schedule

**Files:**
- Modify: `Notiee/Features/Capture/CaptureView.swift` — restructure the Menu

- [ ] **Step 1: Replace the Menu in CaptureView.swift topBar**

Find the `Menu` in `topBar` (~lines 89-99):
```swift
Menu {
    ForEach(viewModel.events) { event in
        Button(event.title) {
            viewModel.selectedEventID = event.id
        }
    }
    
    Divider()
    
    Button("未分类") {
        viewModel.selectedEventID = nil
    }
} label: {
```

Replace with:
```swift
Menu {
    let deduplicatedEvents = deduplicateEvents(viewModel.events)
    let hasActiveSchedule = viewModel.currentEvent != nil && viewModel.selectedEventID == nil
    let activeEvent: ScheduledEvent? = hasActiveSchedule ? viewModel.currentEvent : viewModel.events.first(where: { $0.id == viewModel.selectedEventID })
    
    // 1. Active schedule (if any)
    if let active = activeEvent {
        Button {
            viewModel.selectedEventID = active.id
        } label: {
            HStack {
                Text(active.title)
                Spacer()
                if viewModel.selectedEventID == active.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
    
    // 2. 未分类
    Button {
        viewModel.selectedEventID = nil
    } label: {
        HStack {
            Text("未分类")
            Spacer()
            if viewModel.selectedEventID == nil {
                Image(systemName: "checkmark")
            }
        }
    }
    
    // 3. Divider
    if !deduplicatedEvents.isEmpty {
        Divider()
    }
    
    // 4. Remaining deduplicated events (exclude the active one if already shown)
    ForEach(deduplicatedEvents.filter { $0.id != activeEvent?.id }) { event in
        Button {
            viewModel.selectedEventID = event.id
        } label: {
            HStack {
                Text(event.title)
                Spacer()
                if viewModel.selectedEventID == event.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
} label: {
```

- [ ] **Step 2: Add deduplicateEvents helper function to CaptureView.swift**

Add this private function to the `CaptureView` struct:

```swift
private func deduplicateEvents(_ events: [ScheduledEvent]) -> [ScheduledEvent] {
    var seen: Set<String> = []
    var result: [ScheduledEvent] = []
    for event in events {
        if !seen.contains(event.title) {
            seen.insert(event.title)
            result.append(event)
        }
    }
    return result
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Capture/CaptureView.swift
git commit -m "feat: restructure Capture menu with active schedule pinning, deduplication, and checkmarks"
```

---

## Task 6: Restore BackupRestoreView entry + move iCloud sync to LabFeatures

**Files:**
- Modify: `Notiee/Features/Settings/SettingsView.swift` (MeView) — add BackupRestoreView NavigationLink
- Modify: `Notiee/Features/Settings/BackupRestoreView.swift` — remove "手动同步 iCloud" section
- Modify: `Notiee/Features/Settings/LabFeaturesView.swift` — add "手动同步 iCloud" toggle (placeholder, no implementation)

### 6a: Add BackupRestoreView entry to MeView

- [ ] **Step 1: Add NavigationLink to MeView**

In `MeView` body, add a new section for backup between the existing sections. The current MeView has sections:
1. Login prompt
2. "全部日程" + "导入日程"
3. "回顾"
4. "实验室功能"
5. "设置"

Add a new section after "回顾" and before "实验室功能":

```swift
Section {
    NavigationLink {
        BackupRestoreView(store: store)
    } label: {
        Label("备份与恢复", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
            .foregroundColor(.blue)
    }
}
```

Placed between the Review section closing `}` and the Lab section opening `}`.

### 6b: Remove "手动同步 iCloud" from BackupRestoreView

- [ ] **Step 2: Remove iCloud sync section from BackupRestoreView**

In `BackupRestoreView.swift`, remove the entire `Section` that contains "手动同步 iCloud":

Delete lines 38-50:
```swift
Section {
    Button {
        // TODO: Implement iCloud sync
        print("iCloud sync triggered")
    } label: {
        HStack {
            Image(systemName: "icloud.and.arrow.up")
            Text("手动同步 iCloud")
        }
    }
} footer: {
    Text("将本地记录同步到您的个人 iCloud 空间。（即将推出）")
}
```

### 6c: Add "手动同步 iCloud" placeholder to LabFeaturesView

- [ ] **Step 3: Add iCloud sync toggle to LabFeaturesView**

In `LabFeaturesView.swift`, add a new `@AppStorage` property and a new `Section` at the end of the Form (before the closing `}` of the Form and the closing `VStack`):

Add property at top:
```swift
@AppStorage("labICloudSyncEnabled") private var iCloudSyncEnabled = false
```

Add section before the closing `}` of the Form body:
```swift
Section {
    Toggle(isOn: $iCloudSyncEnabled) {
        Label("手动同步 iCloud", systemImage: "icloud.and.arrow.up")
    }
} footer: {
    Text("将本地记录同步到您的个人 iCloud 空间。（即将推出，敬请期待）")
}
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Notiee/Features/Settings/SettingsView.swift Notiee/Features/Settings/BackupRestoreView.swift Notiee/Features/Settings/LabFeaturesView.swift
git commit -m "feat: restore BackupRestoreView entry in MeView, move iCloud sync to LabFeatures"
```

---

## Final Verification

- [ ] **Run full test suite:**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test 2>&1 | grep -E "(Test Suite|passed|failed|BUILD)"
```

Expected: All 28 tests pass, BUILD SUCCEEDED

- [ ] **Final commit (if no changes needed):**

```bash
git log --oneline -6
```
