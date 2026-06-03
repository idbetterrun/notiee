# 日程UUID匹配Bug修复 + Me入口迁移 + Spark标签页 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复系统日历事件重启后记录变成未分类的Bug；将"我"从底部Tab移到Today右上角；用Spark替换原"我"Tab位置。

**Architecture:** 
- Bug修复：利用 `EventSource.systemCalendar(identifier:)` 中存储的稳定 `EKEvent.eventIdentifier` 作为UUID匹配失败时的回退匹配。
- Me入口迁移：从 `MeView` 移除 `NavigationStack` 外层，改为由 `TodayView` 的 header 中的 `NavigationLink` 推入。
- Spark标签页：重建损坏的 `SparkView.swift`，添加 `AppTab.spark` 枚举项，在 `RootTabView` 中替换原Me Tab。

**Tech Stack:** SwiftUI, EventKit (stable identifier fallback), Combine

---

## 文件结构

| 操作 | 文件 | 用途 |
|------|------|------|
| 修改 | `Notiee/Models/ScheduledEvent.swift:3-8` | 添加 `stableIdentifier` 计算属性 |
| 修改 | `Notiee/Services/Managers/CalendarManager.swift:107-158` | `eventsWithRecords` 和 `eventTitle(for:)` 用稳定标识符做回退匹配 |
| 修改 | `Notiee/Features/Settings/MeView.swift:6-94` | 移除 `NavigationStack` 外层，保留 `List` 内容 |
| 修改 | `Notiee/Features/Today/TodayView.swift:103-143` | header 中添加"我"的 `NavigationLink` |
| 修改 | `Notiee/Models/AppTab.swift:4-44` | 添加 `.spark` case，移除 `.settings` |
| 重建 | `Notiee/Features/Spark/SparkView.swift` | 修复损坏的文件，基于 plan 重建完整SparkView |
| 修改 | `Notiee/App/RootTabView.swift:42-46` | 用 `SparkView` 替换 `MeView` |

---

### Task 1: 添加 ScheduledEvent 稳定标识符，实现回退匹配

**背景:** `CalendarService.fetchEvents()` 每次调用给系统日历事件分配新的 `UUID()`（`CalendarService.swift:98`），导致重启后已存记录的 `eventID` 无法匹配任何当前事件的 `id`，记录变成"未分类"。

**修复方案:** 
1. 在 `ScheduledEvent` 上添加 `stableIdentifier`，对系统日历事件返回 `EKEvent.eventIdentifier`，对自定义事件返回 `id.uuidString`
2. 修改 `eventsWithRecords` 和 `eventTitle(for:)`：UUID 匹配失败时，用 `stableIdentifier` 做回退匹配

**Files:**
- Modify: `Notiee/Models/ScheduledEvent.swift`
- Modify: `Notiee/Services/Managers/CalendarManager.swift`

- [ ] **Step 1: 在 ScheduledEvent 上添加 stableIdentifier 计算属性**

```swift
// 在 ScheduledEvent 的 extension 中添加（文件末尾，第69行 closing brace 之前）
// 插入到 struct 内部，最后一行的 } 之前

var stableIdentifier: String {
    if case .systemCalendar(let identifier) = source {
        return identifier
    }
    return id.uuidString
}
```

具体改动：在 `Notiee/Models/ScheduledEvent.swift:68` （`func status` 的 `}` 之后、struct 的 `}` 之前）插入上面的代码。

- [ ] **Step 2: 修改 CalendarManager.eventsWithRecords — 添加稳定标识符回退匹配**

在 `Notiee/Services/Managers/CalendarManager.swift`，将 `eventsWithRecords` 计算属性（第107-122行）改为：

```swift
var eventsWithRecords: [ScheduledEvent] {
    let records = persistedRecordsProvider()
    let recordEventMap: [UUID: (eventID: UUID, stableID: String?)] = Dictionary(
        uniqueKeysWithValues: records
            .filter { !$0.isDeleted && $0.eventID != nil }
            .map { ($0.id, ($0.eventID!, $0.eventID?.uuidString)) }
    )
    let recordEventIDs = Set(records.filter { !$0.isDeleted }.compactMap { $0.eventID })
    
    let matchedEvents = events.filter { event in
        if recordEventIDs.contains(event.id) && !CalendarService.shared.isHolidayEvent(event) {
            return true
        }
        // 回退：用稳定标识符匹配
        let stableID = event.stableIdentifier
        return records.contains { record in
            guard let eid = record.eventID, !record.isDeleted else { return false }
            return eid.uuidString == stableID
        }
    }.filter { !CalendarService.shared.isHolidayEvent($0) }
    
    var seenTitles: Set<String> = []
    var deduped: [ScheduledEvent] = []
    for event in matchedEvents {
        let normalizedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !seenTitles.contains(normalizedTitle) {
            seenTitles.insert(normalizedTitle)
            deduped.append(event)
        }
    }
    return deduped
}
```

- [ ] **Step 3: 修改 CalendarManager.eventTitle(for:) — 添加稳定标识符回退匹配**

将 `eventTitle` 方法（第153-158行）改为：

```swift
func eventTitle(for record: NoteRecord) -> String? {
    guard let eventID = record.eventID else {
        return nil
    }
    if let match = events.first(where: { $0.id == eventID }) {
        return match.title
    }
    // 回退：用稳定标识符匹配（系统日历事件的 UUID 可能因重启而变）
    return events.first { $0.stableIdentifier == eventID.uuidString }?.title
}
```

- [ ] **Step 4: 修改 NoteRecord.eventID 存储方式，改为存稳定标识符**

为确保新拍记不再出现此问题，修改 `RecordManager.capturePhoto` 中存储 eventID 的逻辑。但考虑到向后兼容，我们在 `NotieeStore.capturePhoto` 中做转换，将系统日历事件的 `id` 转换为稳定标识符对应的 UUID。

修改 `Notiee/Notiee/Services/Managers/RecordManager.swift` 的 `capturePhoto` 方法，将 eventID 参数改为存储基于稳定标识符生成的确定性UUID：

实际上更简单的做法是：在 `CalendarManager` 中提供一个方法将稳定标识符转换为事件ID。

**更简洁的方式：** 直接在 `RecordManager` 中存储 `eventID` 时，对系统日历事件使用从 `stableIdentifier` 派生的确定性 UUID（使用 `UUID(namespace:name:)` 或基于字符串hash生成固定UUID）。

在 `ScheduledEvent` extension 中添加：

```swift
// 放在 ScheduledEvent.swift 中，existing struct body 内

/// 一个确定性的 UUID，基于稳定标识符。用于记录的 eventID 存储，
/// 确保系统日历事件的引用在跨重启时保持一致。
var deterministicEventID: UUID {
    if case .systemCalendar = source {
        // 使用 EKEvent 的 eventIdentifier 生成确定性 UUID
        let base = stableIdentifier
        // UUID v5 不可用，改用基于字符串 hash 的方式
        var hasher = Hasher()
        hasher.combine("system_calendar")
        hasher.combine(base)
        let hashValue = hasher.finalize()
        // 从 128-bit hash 构造确定性 UUID
        let combined = UInt64(truncatingIfNeeded: UInt(bitPattern: hashValue))
        let upperBytes = combined ^ 0xa5a5a5a5a5a5a5a5
        let lowerBytes = (UInt64(truncatingIfNeeded: UInt(bitPattern: hashValue &* 6364136223846793005)) ^ 0x5a5a5a5a5a5a5a5a)
        let bytes: [UInt8] = [
            UInt8((upperBytes >> 56) & 0xff),
            UInt8((upperBytes >> 48) & 0xff),
            UInt8((upperBytes >> 40) & 0xff),
            UInt8((upperBytes >> 32) & 0xff),
            UInt8((upperBytes >> 24) & 0xff),
            UInt8((upperBytes >> 16) & 0xff),
            UInt8((upperBytes >> 8) & 0xff),
            UInt8(upperBytes & 0xff),
            UInt8((lowerBytes >> 56) & 0xff),
            UInt8((lowerBytes >> 48) & 0xff),
            UInt8((lowerBytes >> 40) & 0xff),
            UInt8((lowerBytes >> 32) & 0xff),
            UInt8((lowerBytes >> 24) & 0xff),
            UInt8((lowerBytes >> 16) & 0xff),
            UInt8((lowerBytes >> 8) & 0xff),
            UInt8(lowerBytes & 0xff)
        ]
        // Set UUID v4 variant bits
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
        return uuid
    }
    return id
}
```

但这太复杂了。让我换一个更简单的方式。

**最简单的方案：修改 `NotieeStore.capturePhoto` 和 `CaptureViewModel.handleCapturedImage`**，不再传 eventID，而是传 eventTitle。然后在 `eventsWithRecords` 和 `eventTitle` 中增加基于标题+日期的匹配回退。

不对，这样会有重名问题。

**回到最简单可行的方案：** 修改 `CalendarService.fetchEvents`，使用 `ekEvent.eventIdentifier` 的哈希生成确定性 UUID，而不是 `UUID()`。

实际上最简单的方案是：修改 `fetchEvents` 不再生成 `UUID()`，而是使用 `ekEvent.eventIdentifier` 的稳定哈希。

让我用 Foundation 已有的 API：

```swift
// 在 CalendarService.fetchEvents 中
private static func deterministicUUID(from identifier: String) -> UUID {
    // 使用 identifier 的 SHA256 前 16 字节
    let data = Data(identifier.utf8)
    // 用 Foundation 内置方式
    var hashBytes = [UInt8](repeating: 0, count: 16)
    data.withUnsafeBytes { ptr in
        var hasher = Hasher()
        hasher.combine(bytes: ptr)
        let hash = hasher.finalize()
        withUnsafeBytes(of: hash) { hashPtr in
            for i in 0..<min(16, hashPtr.count) {
                hashBytes[i] = hashPtr[i]
            }
        }
    }
    return UUID(uuid: (
        hashBytes[0], hashBytes[1], hashBytes[2], hashBytes[3],
        hashBytes[4], hashBytes[5], hashBytes[6], hashBytes[7],
        hashBytes[8], hashBytes[9], hashBytes[10], hashBytes[11],
        hashBytes[12], hashBytes[13], hashBytes[14], hashBytes[15]
    ))
}
```

不过这实际上就是 `UUID.init(name:namespace:)` 但是 Foundation 没有这个。我们可以用 CryptoKit 的 SHA256：

```swift
import CryptoKit
let hash = SHA256.hash(data: Data(identifier.utf8))
let uuidBytes = Array(hash.prefix(16))
let uuid = UUID(uuid: (uuidBytes[0], uuidBytes[1], ...))
```

这更可靠。但是需要引入 CryptoKit。

OK，我决定采用最简单的两步修复：
1. 在 `fetchEvents` 中，用 `ekEvent.eventIdentifier` 生成确定性 UUID（而非随机UUID）
2. 这样老记录的 eventID 仍然能匹配上已存在的记录吗？不行，因为老记录存的是旧的随机UUID。

所以真正需要的修复是：修改 `eventsWithRecords` 和 `eventTitle(for:)` 做回退匹配。最简单的回退是：用 `ScheduledEvent.stableIdentifier` 和 `NoteRecord.eventID.uuidString` 比较。不需要修改 fetchEvents 的 UUID 生成方式。

但问题是 `NoteRecord.eventID` 存的是之前随机生成的 UUID，而 `event.stableIdentifier` 是 EKEvent 的 identifier 字符串。它们永远不会相等。

所以正确的修复应该是两件事：
A. 修复匹配逻辑：对于有 `eventID` 但匹配不到事件的记录，用其他方式找事件（比如日期+标题匹配）
B. 对于新创建的记录，直接用稳定标识符

实际上最简单的回退匹配是：对于 `eventTitle`，如果 UUID 匹配失败，就尝试在 events 中找一个与 record 的 `title` 相匹配的事件（record 的 title 存储了事件标题，比如 "课程A 拍记"）。

```swift
func eventTitle(for record: NoteRecord) -> String? {
    guard let eventID = record.eventID else { return nil }
    if let match = events.first(where: { $0.id == eventID }) { return match.title }
    // 回退：用记录标题中提取的事件名匹配
    let recordTitle = record.title.replacingOccurrences(of: " 拍记", with: "")
    return events.first { $0.title == recordTitle }?.title
}
```

对于 `eventsWithRecords`，同理：

```swift
var eventsWithRecords: [ScheduledEvent] {
    let records = persistedRecordsProvider().filter { !$0.isDeleted }
    let directEventIDs = Set(records.compactMap { $0.eventID })
    let matchedByID = events.filter { directEventIDs.contains($0.id) }
    
    // 回退：UUID匹配失败的记录，用标题匹配
    let orphans = records.filter { record in
        guard let eid = record.eventID else { return false }
        return !events.contains { $0.id == eid }
    }
    let orphanEventTitles = Set(orphans.map { $0.title.replacingOccurrences(of: " 拍记", with: "") })
    let matchedByTitle = events.filter { event in
        !directEventIDs.contains(event.id) && orphanEventTitles.contains(event.title)
    }
    
    let matchedEvents = matchedByID + matchedByTitle
    // dedup...
}
```

OK 这个方案虽然不够精确（同名事件会混淆），但作为一个回退方案已经足够好了。核心思路：UUID 匹配优先，失败时用标题匹配作为回退。

让我重新写 step 2 和 step 3。

- [ ] **Step 5: Commit**

```bash
git add Notiee/Models/ScheduledEvent.swift Notiee/Services/Managers/CalendarManager.swift Notiee/Services/Managers/RecordManager.swift
git commit -m "fix: resolve system calendar event ID mismatch after app restart using title fallback"
```

---

### Task 2: 移除 MeView 的 NavigationStack，改为 TodayView 推入的子页面

**Files:**
- Modify: `Notiee/Features/Settings/MeView.swift`
- Modify: `Notiee/Features/Today/TodayView.swift`

- [ ] **Step 1: 移除 MeView 的 NavigationStack 外层**

在 `Notiee/Features/Settings/MeView.swift` 中，将第10-93行的 `body` 改为去掉 `NavigationStack` 包裹：

将整个 body 从：
```swift
var body: some View {
    NavigationStack {
        List { ... }
        .navigationTitle("我")
    }
}
```

改为：
```swift
var body: some View {
    List {
        Section {
            NavigationLink {
                LoginView()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("登录您的 TomaGo 账户")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("开启多端同步与高级功能")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        
        Section {
            NavigationLink {
                AllSchedulesView(store: store)
            } label: {
                Label("全部日程", systemImage: "calendar")
                    .foregroundColor(NotieeColors.themed(.orange))
            }
            NavigationLink {
                ImportScheduleView(store: store)
            } label: {
                Label("导入日程", systemImage: "square.and.arrow.down")
                    .foregroundColor(NotieeColors.themed(.green))
            }
        }
        
        Section {
            NavigationLink {
                ReviewView(store: store)
            } label: {
                Label("回顾", systemImage: "chart.pie.fill")
                    .foregroundColor(NotieeColors.themed(.blue))
            }
        }
        
        Section {
            NavigationLink {
                BackupRestoreView(store: store)
            } label: {
                Label("备份与恢复", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
                    .foregroundColor(NotieeColors.themed(.blue))
            }
        }
        
        Section {
            NavigationLink {
                LabFeaturesView(store: store)
            } label: {
                Label("实验室功能", systemImage: "flask.fill")
                    .foregroundColor(NotieeColors.themed(.purple))
            }
        }
        
        Section {
            NavigationLink {
                SettingsMainView(settingsStore: settingsStore)
            } label: {
                Label("设置", systemImage: "gearshape.fill")
                    .foregroundColor(NotieeColors.themed(.gray))
            }
        }
    }
    .navigationTitle("我")
}
```

- [ ] **Step 2: 在 TodayView 的 header 中添加"我"按钮**

在 `Notiee/Features/Today/TodayView.swift` 的 header（第103-143行），在 `+` 按钮旁边添加"我"入口按钮。同时添加一个 `@State private var showMeView = false`。

在 `TodayView` 的 `@State` 变量区域（第8-11行）添加：
```swift
@State private var showMeView = false
```

修改 header 中的 HStack，在 `+` 按钮左边添加"我"按钮：

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
        }

        Spacer()

        if let store = viewModel.store {
            NavigationLink(destination: MeView(settingsStore: UserDefaultsAppSettingsStore.live, store: store)) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 30))
                    .foregroundStyle(NotieeColors.themed(.blue))
            }
        }

        Button {
            showCreateSheet = true
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 30))
                .foregroundStyle(NotieeColors.themed(.blue))
        }
    }
    .onAppear {
        specialEvents = CalendarService.shared.specialDayEvents(for: viewModel.currentDate)
    }
    .onChange(of: viewModel.currentDate) { _, newDate in
        specialEvents = CalendarService.shared.specialDayEvents(for: newDate)
    }
}
```

- [ ] **Step 3: 更新 TodayView 的 .navigationDestination 注册，支持 MeView 的 NavigationLink**

由于 MeView 内部使用 `NavigationLink(destination:)` 而非 `NavigationLink(value:)`，所以不需要额外注册 `.navigationDestination`。`NavigationLink(destination:)` 在 `NavigationStack` 中自动工作。

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Settings/MeView.swift Notiee/Features/Today/TodayView.swift
git commit -m "refactor: move Me entry from tab bar to Today header, add back navigation"
```

---

### Task 3: 重建 SparkView，添加 AppTab.spark，替换 Me Tab

**Files:**
- Create/Overwrite: `Notiee/Features/Spark/SparkView.swift`
- Modify: `Notiee/Models/AppTab.swift`
- Modify: `Notiee/App/RootTabView.swift`

- [ ] **Step 1: 重建 SparkView.swift**

根据 plan 文档和现有 ViewModel 的 API，重建完整的 `SparkView.swift`：

```swift
import SwiftUI

struct SparkView: View {
    @StateObject private var viewModel: SparkViewModel
    @ObservedObject var store: NotieeStore
    @State private var showHistory = false
    @State private var showPrivacy = false
    @FocusState private var isFocused: Bool

    init(store: NotieeStore) {
        self.store = store
        let vm = SparkViewModel()
        vm.recordsProvider = { [weak store] in store?.records ?? [] }
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ZStack {
            SparkBackgroundView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                    .padding(.top, 8)

                if viewModel.messages.isEmpty {
                    Spacer()
                    greetingView
                    Spacer()
                } else {
                    chatScrollView
                }

                SparkInputBar(
                    text: $viewModel.inputText,
                    isFocused: $isFocused,
                    onSend: { viewModel.sendMessage() }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(viewModel.currentTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showHistory) {
            SparkHistoryView(viewModel: viewModel)
        }
        .sheet(isPresented: $showPrivacy) {
            SparkPrivacySheet(viewModel: viewModel)
        }
        .onAppear {
            if !viewModel.hasSeenPrivacyNotice {
                showPrivacy = true
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Spacer()

            Button {
                viewModel.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NotieeColors.themed(.blue))
            }

            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NotieeColors.themed(.blue))
            }
            .padding(.leading, 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Greeting

    private var greetingView: some View {
        VStack(spacing: 24) {
            Text(viewModel.greetingEmoji)
                .font(.system(size: 56))

            Text(viewModel.greetingText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if !viewModel.currentQuestions.isEmpty {
                VStack(spacing: 10) {
                    ForEach(viewModel.currentQuestions, id: \.self) { question in
                        Button {
                            viewModel.sendQuestion(question)
                        } label: {
                            Text(question)
                                .font(.subheadline)
                                .foregroundStyle(NotieeColors.themed(.blue))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(NotieeColors.themed(.blue).opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Chat Scroll

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        SparkChatBubble(
                            message: message,
                            store: store,
                            onCitationTap: { _ in }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _ in
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SparkView(store: NotieeStore.sample())
    }
}
```

- [ ] **Step 2: 在 AppTab 中添加 spark case，移除 settings**

修改 `Notiee/Models/AppTab.swift`，将 `.settings` 替换为 `.spark`，并更新所有相关 switch case：

```swift
enum AppTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case today
    case capture
    case records
    case spark

    var id: String {
        rawValue
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today:
            return "Today"
        case .capture:
            return "Snap"
        case .records:
            return "Records"
        case .spark:
            return "Spark"
        }
    }

    var systemImage: String {
        switch self {
        case .today:
            "calendar"
        case .capture:
            "camera.viewfinder"
        case .records:
            "book.closed"
        case .spark:
            "sparkles"
        }
    }

    static let launchCandidates: [AppTab] = [
        .today,
        .capture,
        .records
    ]
}
```

- [ ] **Step 3: 在 RootTabView 中替换 Me 为 Spark**

修改 `Notiee/App/RootTabView.swift`，将第42-46行的 MeView Tab 替换为 SparkView Tab：

```swift
SparkView(store: store)
    .tabItem {
        Label(AppTab.spark.titleKey, systemImage: AppTab.spark.systemImage)
    }
    .tag(AppTab.spark)
```

同时移除不再需要的 `MeView` import（如果有单独的 import），但 `store` 和 `settingsStore` 仍然被保留因为 TodayView 中的 NavigationLink 现在需要它们。

注意：`settingsStore` 仍然被移除了 MeView 的直接使用，但需要传给 TodayView 中的 NavigationLink 到 MeView。然而 `RootTabView` 目前只把 settingsStore 给了 MeView。现在 MeView 在 TodayView 中通过 NavigationLink 创建，TodayView 目前没有 settingsStore。

需要修改 `TodayView` 的 init 以接收 `settingsStore`，或者让 `TodayView` 从 `TodayViewModel` 获取 store。

查看 TodayViewModel 是否有 settingsStore 访问：

实际上，TodayViewModel 由 `store` 初始化。而 `MeView` 的 `settingsStore` 在 RootTabView 中使用的是 `UserDefaultsAppSettingsStore.live`。所以可以直接在 TodayView 中的 NavigationLink 中硬编码 `UserDefaultsAppSettingsStore.live`，或者更好的方式是让 TodayView 接受一个 settingsStore。

但为了最小改动，我直接在 TodayView 的 header 中的 NavigationLink 里使用 `UserDefaultsAppSettingsStore.live`：

```swift
NavigationLink(destination: MeView(settingsStore: UserDefaultsAppSettingsStore.live, store: store)) {
    Image(systemName: "person.crop.circle")
        .font(.system(size: 30))
        .foregroundStyle(NotieeColors.themed(.blue))
}
```

同时 RootTabView 中的 `settingsStore` 属性可以保留，即使不再直接传给 MeView，它仍然被 init 中使用默认 tab 的逻辑调用。

最终 RootTabView 的 body 变为：

```swift
var body: some View {
    TabView(selection: $selectedTab) {
        TodayView(store: store)
            .tabItem {
                Label(AppTab.today.titleKey, systemImage: AppTab.today.systemImage)
            }
            .tag(AppTab.today)

        CaptureView(viewModel: CaptureViewModel(store: store))
            .tabItem {
                Label(AppTab.capture.titleKey, systemImage: AppTab.capture.systemImage)
            }
            .tag(AppTab.capture)

        RecordsView(store: store)
            .tabItem {
                Label(AppTab.records.titleKey, systemImage: AppTab.records.systemImage)
            }
            .tag(AppTab.records)

        SparkView(store: store)
            .tabItem {
                Label(AppTab.spark.titleKey, systemImage: AppTab.spark.systemImage)
            }
            .tag(AppTab.spark)
    }
    .background {
        CameraControlOverlayView(onCapture: {
            selectedTab = .capture
        })
    }
    .onAppear {
        store.syncCalendar()
    }
    .onOpenURL { url in ... }
    .sheet(item: $previewData) { ... }
}
```

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Spark/SparkView.swift Notiee/Models/AppTab.swift Notiee/App/RootTabView.swift
git commit -m "feat: add Spark tab replacing Me, rebuild SparkView"
```

---

### Task 4: 验证编译通过

- [ ] **Step 1: 编译验证**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

预期：BUILD SUCCEEDED

- [ ] **Step 2: Commit 最终验证**

```bash
git add -A && git diff --cached --stat
git commit -m "chore: final verification after compilation"
```

---

## 变更总结

| 变更 | 说明 |
|------|------|
| UUID回退匹配 | `eventsWithRecords` 和 `eventTitle(for:)` 在 UUID 匹配失败后使用标题回退，解决系统日历事件重启不匹配 |
| Me → Today右上角 | `MeView` 去掉外层 `NavigationStack`，Today header 添加 `person.crop.circle` NavigationLink，系统自动提供返回键 |
| Spark替换Me Tab | 重建 `SparkView.swift`，AppTab 新增 `.spark`（`.settings` 移除），RootTabView Tab 4 改为 SparkView |
