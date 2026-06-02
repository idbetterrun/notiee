# Today Page & Capture Menu Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Live Activity toggle on Today event cards, support multiple holiday/birthday displays, classify all-day events (special vs general), skip Live Activity for all-day events, and improve Capture menu with 3-item pinning.

**Architecture:** New `SpecialDayEvent` struct for holiday display. `ScheduledEvent` gains `isAllDay` property. `CalendarService` enhanced for multi-event detection and all-day classification. `NotieeStore` gets `liveActivityDisabledEventIDs` for per-event toggle. Capture menu restructured with 3-item pinning and holiday filtering.

**Tech Stack:** SwiftUI, EventKit, ActivityKit, Combine

---

### Task 1: Add `isAllDay` to ScheduledEvent + populate from CalendarService

**Files:**
- Modify: `Notiee/Models/ScheduledEvent.swift` — add `isAllDay: Bool`
- Modify: `Notiee/Services/CalendarService.swift` — set `isAllDay` from `EKEvent.isAllDay`

- [ ] **Step 1: Add `isAllDay` property to ScheduledEvent**

In `ScheduledEvent.swift`, add the property to the struct and init:

```swift
var isAllDay: Bool

init(
    id: UUID = UUID(),
    title: String,
    startDate: Date,
    endDate: Date,
    kind: Kind = .course,
    tagID: UUID? = nil,
    updatedAt: Date = Date(),
    source: EventSource = .notiee,
    notes: String? = nil,
    isAllDay: Bool = false
) {
    ...
    self.isAllDay = isAllDay
}
```

- [ ] **Step 2: Set `isAllDay` from EKEvent in CalendarService.fetchEvents**

In the `ekEvents.map` closure in `CalendarService.fetchEvents`, add `isAllDay: ekEvent.isAllDay` to the `ScheduledEvent` initializer.

Also add `isAllDay: false` wherever `ScheduledEvent` is instantiated in `NotieeStore.sample()` and any test files that construct `ScheduledEvent`.

- [ ] **Step 3: Verify build and fix all compilation errors**

Run: `xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:|BUILD" | head -20`

Fix any missing `isAllDay:` arguments in test files, sample data, etc.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add isAllDay property to ScheduledEvent, populate from EKEvent"
```

---

### Task 2: Enhance holiday/birthday detection with multi-event support and classification

**Files:**
- Create: `Notiee/Models/SpecialDayEvent.swift` — new model struct
- Modify: `Notiee/Services/CalendarService.swift` — replace `holidayOrBirthdayText` with multi-event version

- [ ] **Step 1: Create SpecialDayEvent model**

New file `Notiee/Models/SpecialDayEvent.swift`:

```swift
import SwiftUI

struct SpecialDayEvent: Identifiable {
    enum EventType {
        case holiday    // 节日
        case birthday   // 生日
        case solarTerm  // 节气
    }
    
    let id = UUID()
    let title: String
    let type: EventType
    
    var color: Color {
        switch type {
        case .holiday: return .red
        case .birthday: return .pink
        case .solarTerm: return .green
        }
    }
}
```

- [ ] **Step 2: Replace `holidayOrBirthdayText` with `specialDayEvents` in CalendarService**

In `CalendarService.swift`, replace the `holidayOrBirthdayText(for:)` method with:

```swift
func specialDayEvents(for date: Date) -> [SpecialDayEvent] {
    guard isAuthorized else { return [] }
    
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: date)
    guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return [] }
    
    let allowedIDs = selectedCalendarIDs()
    let filteredCalendars = allowedIDs.isEmpty
        ? eventStore.calendars(for: .event)
        : eventStore.calendars(for: .event).filter { allowedIDs.contains($0.calendarIdentifier) }
    
    let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: filteredCalendars)
    let events = eventStore.events(matching: predicate)
    
    var results: [SpecialDayEvent] = []
    
    for ekEvent in events {
        // Birthday
        if ekEvent.calendar?.type == .birthday, let title = ekEvent.title {
            results.append(SpecialDayEvent(title: title, type: .birthday))
            continue
        }
        
        let calTitle = ekEvent.calendar?.title ?? ""
        let isHolidayCalendar = calTitle.contains("节") || calTitle.contains("假日") || calTitle.contains("Holiday") || calTitle.contains("节日")
        
        if isHolidayCalendar, let title = ekEvent.title {
            // Check for solar terms (节气) — typically short titles with specific characters
            if isSolarTerm(title) {
                results.append(SpecialDayEvent(title: title, type: .solarTerm))
            } else {
                results.append(SpecialDayEvent(title: title, type: .holiday))
            }
            continue
        }
        
        let eventTitle = ekEvent.title ?? ""
        if eventTitle.contains("生日") || eventTitle.localizedCaseInsensitiveContains("birthday") {
            results.append(SpecialDayEvent(title: eventTitle, type: .birthday))
            continue
        }
        
        // Short festival names
        if eventTitle.contains("节") && eventTitle.count < 20 && !eventTitle.contains("节目") && !eventTitle.contains("环节") {
            if isSolarTerm(eventTitle) {
                results.append(SpecialDayEvent(title: eventTitle, type: .solarTerm))
            } else {
                results.append(SpecialDayEvent(title: eventTitle, type: .holiday))
            }
        }
    }
    
    return results
}

private func isSolarTerm(_ title: String) -> Bool {
    let solarTerms = ["立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
                      "立夏", "小满", "芒种", "夏至", "小暑", "大暑",
                      "立秋", "处暑", "白露", "秋分", "寒露", "霜降",
                      "立冬", "小雪", "大雪", "冬至", "小寒", "大寒"]
    return solarTerms.contains(where: { title.contains($0) })
}
```

Also keep the old `holidayOrBirthdayText` method for backward compatibility — it delegates to `specialDayEvents`:
```swift
func holidayOrBirthdayText(for date: Date) -> String? {
    specialDayEvents(for: date).first?.title
}
```

- [ ] **Step 3: Add `isSpecialAllDayEvent` helper to CalendarService**

```swift
func isSpecialAllDayEvent(_ event: ScheduledEvent) -> Bool {
    guard event.isAllDay else { return false }
    let events = specialDayEvents(for: event.startDate)
    return events.contains(where: { $0.title == event.title })
}
```

- [ ] **Step 4: Verify build**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5
```

The `SpecialDayEvent.swift` file needs to be added to the Xcode project. If automatic file addition doesn't work, the implementer should also update `project.pbxproj` to include the new file.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add multi-event holiday/birthday support with SpecialDayEvent model and classification"
```

---

### Task 3: Today page — multiple holiday/birthday display with different colors

**Files:**
- Modify: `Notiee/Features/Today/TodayView.swift` — change single `holidayText` to multi-event display

- [ ] **Step 1: Replace `holidayText: String?` with `specialEvents: [SpecialDayEvent]`**

At top of `TodayView` struct:

```swift
@State private var holidayText: String?
```
Replace with:
```swift
@State private var specialEvents: [SpecialDayEvent] = []
```

- [ ] **Step 2: Update the header badge section**

Replace the single holiday badge:
```swift
if let holiday = holidayText {
    Text(holiday)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
}
```

With a horizontal scroll or wrap of multiple badges:
```swift
if !specialEvents.isEmpty {
    HStack(spacing: 8) {
        ForEach(specialEvents) { event in
            Text(event.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(event.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(event.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
```

- [ ] **Step 3: Update the onAppear and onChange**

```swift
.onAppear {
    specialEvents = CalendarService.shared.specialDayEvents(for: viewModel.currentDate)
}
.onChange(of: viewModel.currentDate) { _, newDate in
    specialEvents = CalendarService.shared.specialDayEvents(for: newDate)
}
```

- [ ] **Step 4: Verify build and commit**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
git add Notiee/Features/Today/TodayView.swift && git commit -m "feat: support multiple holiday/birthday displays with per-type colors on Today page"
```

---

### Task 4: Today page — Live indicator on current event cards

**Files:**
- Modify: `Notiee/Features/Today/TodayView.swift` — add Live toggle to EventCard
- Modify: `Notiee/Services/NotieeStore.swift` — add `liveActivityDisabledEventIDs`, modify `updateLiveActivity`

- [ ] **Step 1: Add `liveActivityDisabledEventIDs` to NotieeStore**

Add property:
```swift
@Published private(set) var liveActivityDisabledEventIDs: Set<UUID> = []
```

Persist to UserDefaults in init and on change (like `ignoredCalendarEventKeys` pattern):

```swift
if let data = UserDefaults.standard.data(forKey: "notiee.liveActivityDisabledEventIDs"),
   let decoded = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
    self.liveActivityDisabledEventIDs = decoded
}
```

Add method:
```swift
func toggleLiveActivityDisabled(for eventID: UUID) {
    if liveActivityDisabledEventIDs.contains(eventID) {
        liveActivityDisabledEventIDs.remove(eventID)
    } else {
        liveActivityDisabledEventIDs.insert(eventID)
        LiveActivityManager.shared.endActivity()
    }
    if let data = try? JSONEncoder().encode(liveActivityDisabledEventIDs) {
        UserDefaults.standard.set(data, forKey: "notiee.liveActivityDisabledEventIDs")
    }
    Task { await updateLiveActivity() }
}
```

- [ ] **Step 2: Modify `updateLiveActivity` to respect disabled set and all-day events**

Add two conditions before starting Live Activity:

```swift
func updateLiveActivity() async {
    let isEnabled = UserDefaults.standard.bool(forKey: "notiee.liveActivityEnabled")
    guard isEnabled else {
        LiveActivityManager.shared.endActivity()
        return
    }
    
    let checkDate = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ? currentDate : Date()
    
    if let event = scheduleMatcher.currentEvent(from: events, at: checkDate) {
        // Skip all-day events
        guard !event.isAllDay else {
            LiveActivityManager.shared.endActivity()
            return
        }
        // Skip if user manually disabled Live Activity for this event
        guard !liveActivityDisabledEventIDs.contains(event.id) else {
            LiveActivityManager.shared.endActivity()
            return
        }
        LiveActivityManager.shared.startActivity(for: event)
    } else {
        LiveActivityManager.shared.endActivity()
    }
}
```

- [ ] **Step 3: Add Live toggle button to EventCard in TodayView**

Modify `EventCard` to accept the store and a disabled flag. Add a Live indicator on the right side:

```swift
private struct EventCard: View {
    let event: ScheduledEvent
    let currentDate: Date
    let tag: EventTag?
    let isLiveDisabled: Bool
    let onToggleLive: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Tag badge (existing)
            Text(tag?.name ?? "普通")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(tag?.color ?? .secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(timeRange)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)
            
            // Live toggle — only show for current (non-all-day) events
            if event.status(at: currentDate) == .current && !event.isAllDay {
                Button(action: onToggleLive) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(isLiveDisabled ? Color.secondary : Color.green)
                            .frame(width: 6, height: 6)
                        Text("Live")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isLiveDisabled ? .secondary : .green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isLiveDisabled ? Color.secondary.opacity(0.1) : Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
```

- [ ] **Step 4: Update call sites of EventCard in TodayView**

The `timelineStatusGroup` renders `EventCard` in a `ForEach`. Update to pass the new parameters. The store is available via `viewModel.store`. Update the call to:

```swift
EventCard(
    event: event,
    currentDate: viewModel.currentDate,
    tag: viewModel.store?.customTags.first(where: { $0.id == event.tagID }),
    isLiveDisabled: viewModel.store?.liveActivityDisabledEventIDs.contains(event.id) ?? false,
    onToggleLive: {
        viewModel.store?.toggleLiveActivityDisabled(for: event.id)
    }
)
```

Apply this to ALL three `timelineStatusGroup` calls (已完成, 正在进行, 即将到来) since they all show EventCard.

- [ ] **Step 5: Verify build and commit**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
git add Notiee/Features/Today/TodayView.swift Notiee/Services/NotieeStore.swift && git commit -m "feat: add Live toggle on current event cards, skip Live Activity for all-day and disabled events"
```

---

### Task 5: Today page — General all-day events in "正在进行" section

**Files:**
- Modify: `Notiee/Features/Today/TodayViewModel.swift` — filter completed events to exclude general all-day, include all-day in "正在进行"
- Modify: `Notiee/Features/Today/TodayView.swift` — show all-day indicator on event cards

- [ ] **Step 1: Ensure general all-day events appear in "正在进行"**

In `TodayViewModel`, the `completedEvents`, `currentEvents`, `upcomingEvents` computed properties filter by `status(at: currentDate)`. 

The `status(at:)` method is:
```swift
func status(at date: Date) -> Status {
    if contains(date) { return .current }
    return date < startDate ? .upcoming : .completed
}
```

For an all-day event, `contains(date)` returns true if `startDate <= date < endDate`. For today's date, an all-day event starting today at 00:00 and ending tomorrow at 00:00 would have `contains(currentDate) == true`, so it would be `.current` and appear in "正在进行". This is already correct.

The key change: general all-day events should be **included** in "正在进行" section, and they should have a visual indicator showing they are all-day events. No code change needed for the filtering logic — just add a visual indicator.

- [ ] **Step 2: Add all-day indicator to EventCard**

In `EventCard`'s `VStack`, add an all-day label for all-day events:

```swift
VStack(alignment: .leading, spacing: 4) {
    Text(event.title)
        .font(.headline)
        .lineLimit(1)
    if event.isAllDay {
        Text("全天")
            .font(.caption.weight(.medium))
            .foregroundStyle(.purple)
    } else {
        Text(timeRange)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 3: Ensure general all-day events do NOT appear in holiday/birthday area**

The `specialDayEvents(for:)` method already only returns events classified as special (holiday/birthday/solarTerm). General all-day events won't be included. No change needed.

- [ ] **Step 4: Verify build and commit**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
git add Notiee/Features/Today/TodayView.swift && git commit -m "feat: show all-day indicator on event cards, classify general vs special all-day events"
```

---

### Task 6: Capture menu — 3-item pinning + holiday filtering

**Files:**
- Modify: `Notiee/Features/Capture/CaptureView.swift` — restructure pinned area

- [ ] **Step 1: Add today's all-day event detection to CaptureViewModel**

In `CaptureViewModel.swift`, add a computed property:

```swift
var todayAllDayEvent: ScheduledEvent? {
    let calendar = Calendar.current
    return events.first { event in
        event.isAllDay && calendar.isDate(event.startDate, inSameDayAs: currentDate)
    }
}
```

- [ ] **Step 2: Restructure Capture menu with 3 pinned items**

In `CaptureView.swift`, replace the current Menu structure. The pinned area should be:

1. **[全天事件]** (if `viewModel.todayAllDayEvent != nil`, shows its title) — selecting it sets `selectedEventID` to the all-day event's ID
2. **[当前非全天事件]** (if `viewModel.currentEvent != nil && !viewModel.currentEvent!.isAllDay`) — the currently active non-all-day event
3. **[未分类]** (always) — sets `selectedEventID = nil`

Below divider: remaining schedules, deduplicated by title, **excluding** events whose titles match a special day event (holiday/birthday/solarTerm) UNLESS today IS that holiday.

Menu structure:
```swift
Menu {
    let deduplicated = deduplicateEvents(viewModel.events)
    let todayAllDay = viewModel.todayAllDayEvent
    let currentNonAllDay = viewModel.currentEvent.flatMap { $0.isAllDay ? nil : $0 }
    let todaySpecials = CalendarService.shared.specialDayEvents(for: viewModel.currentDate)
    let todaySpecialTitles = Set(todaySpecials.map { $0.title })
    
    // 1. 全天事件
    if let allDay = todayAllDay {
        Button {
            viewModel.selectedEventID = allDay.id
        } label: {
            HStack {
                Text(allDay.title)
                Spacer()
                if viewModel.selectedEventID == allDay.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
    
    // 2. 当前非全天事件
    if let current = currentNonAllDay {
        Button {
            viewModel.selectedEventID = current.id
        } label: {
            HStack {
                Text(current.title)
                Spacer()
                if viewModel.selectedEventID == current.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
    
    // 3. 未分类
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
    
    // Divider + remaining (filtered)
    let remaining = deduplicated.filter { event in
        event.id != todayAllDay?.id && event.id != currentNonAllDay?.id
    }
    // Exclude holidays/birthdays from remaining list unless today IS that holiday
    .filter { event in
        if todaySpecialTitles.contains(event.title) {
            return true  // Show if today IS this holiday
        }
        // Check if this event is a holiday/birthday/solarTerm type
        return !CalendarService.shared.isSpecialAllDayEvent(event)
    }
    
    if !remaining.isEmpty {
        Divider()
        ForEach(remaining) { event in
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
    }
} label: { ... }
```

- [ ] **Step 3: Verify build and commit**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
git add Notiee/Features/Capture/CaptureView.swift Notiee/Features/Capture/CaptureViewModel.swift && git commit -m "feat: restructure Capture menu with 3-item pinning and holiday filtering"
```

---

## Final Verification

- [ ] **Build and push:**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: **BUILD SUCCEEDED**

- [ ] **Review git log:**

```bash
git log --oneline -6
```
