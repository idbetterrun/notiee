import SwiftUI
import Combine
import UIKit

// 新 UI 预览：实验室里的 Today 2.0 骨架。不接主 App 的任何数据或界面流程。
// Hero 规则选择 + bounded slots + 下拉相机 / 上拉音频手势状态机均为 mock 实现，仅用于预览方向。

enum NewUIPreviewTab: Equatable {
    case today
    case records
}

typealias NewUIPreviewDestination = NewUIPreviewTab

enum NewUIPreviewTodaySection: String, CaseIterable, Identifiable {
    case records
    case todos
    case schedule

    var id: String { rawValue }
}

enum NewUIPreviewRecordsFilter: String, CaseIterable, Identifiable, Hashable {
    case all
    case photo
    case audio
    case text
    case notti

    var id: String { rawValue }

    func includes(_ source: NewUIPreviewRecordSource) -> Bool {
        switch self {
        case .all: return true
        case .photo: return source == .photo
        case .audio: return source == .audio
        case .text: return source == .text
        case .notti: return source == .notti
        }
    }
}

enum NewUIPreviewRecordsScope: Equatable, Hashable, Identifiable {
    case all
    case favorites
    case unclassified
    case today
    case pending
    case trash
    case folder(String)
    case event(String)

    var id: String {
        switch self {
        case .all: return "all"
        case .favorites: return "favorites"
        case .unclassified: return "unclassified"
        case .today: return "today"
        case .pending: return "pending"
        case .trash: return "trash"
        case .folder(let name): return "folder-\(name)"
        case .event(let name): return "event-\(name)"
        }
    }

    var title: String {
        switch self {
        case .all: return String(localized: "记录")
        case .favorites: return String(localized: "收藏夹")
        case .unclassified: return String(localized: "未分类")
        case .today: return String(localized: "今日拍记")
        case .pending: return String(localized: "待处理")
        case .trash: return String(localized: "回收站")
        case .folder(let name), .event(let name): return name
        }
    }
}

enum NewUIPreviewRecordOrigin: String, Hashable {
    case today
    case records
}

enum NewUIPreviewOverlay: Identifiable, Equatable {
    case module(NewUIPreviewTodaySection)
    case recordDetail(recordID: UUID, origin: NewUIPreviewRecordOrigin)

    var id: String {
        switch self {
        case .module(let section): return "module-\(section.rawValue)"
        case .recordDetail(let recordID, let origin):
            return "record-\(origin.rawValue)-\(recordID.uuidString)"
        }
    }
}

enum NewUIPreviewHeroContext: Equatable {
    case activeEvent
    case dueTodo
    case imminentEvent
    case recordMomentum
    case calm

    /// Execution Heroes (an active/imminent event or a due todo) pair with an actionable-todos
    /// review slot; reflection/calm Heroes pair with a today-records review slot. Mirrors the
    /// design spec's Hero→review-slot rule (docs/superpowers/specs/2026-07-29-today-2-context-dashboard-design.md).
    var isExecution: Bool {
        switch self {
        case .activeEvent, .dueTodo, .imminentEvent: return true
        case .recordMomentum, .calm: return false
        }
    }

    var recommendedTodaySection: NewUIPreviewTodaySection {
        switch self {
        case .activeEvent, .imminentEvent: return .schedule
        case .dueTodo: return .todos
        case .recordMomentum, .calm: return .records
        }
    }

    var showsAurora: Bool { self == .activeEvent }
}

/// Lets the lab preview jump directly to any of the design spec's five priority-ordered Hero
/// states, instead of relying on brittle substring matching over mock copy.
enum NewUIPreviewScenario: String, CaseIterable, Identifiable {
    case activeEvent
    case dueTodo
    case imminentEvent
    case recordMomentum
    case calm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activeEvent: return String(localized: "进行中的日程")
        case .dueTodo: return String(localized: "临近截止的待办")
        case .imminentEvent: return String(localized: "即将开始的日程")
        case .recordMomentum: return String(localized: "今日记录较多")
        case .calm: return String(localized: "安静，无紧急事项")
        }
    }
}

struct NewUIPreviewHero: Equatable {
    let context: NewUIPreviewHeroContext
    let title: String
    let supporting: String
}

/// Tags a mock urgent item with which spec priority tier it represents, so Hero selection can
/// switch on structured data instead of matching substrings in display copy.
enum NewUIPreviewUrgentKind: Equatable {
    case activeEvent
    case dueTodo
    case imminentEvent
}

struct NewUIPreviewUrgentItem: Identifiable, Equatable {
    let id: UUID
    let kind: NewUIPreviewUrgentKind
    let title: String
    let detail: String
}

struct NewUIPreviewTodayRecord: Identifiable, Equatable {
    let id: UUID
    let title: String
    let summary: String
    let thumbnailImageName: String?
}

struct NewUIPreviewStatistics: Equatable {
    let todayCount: Int
    let consecutiveDays: Int
}

enum NewUIPreviewSharedReviewSlot {
    case todos([NewUIPreviewUrgentItem])
    case todayRecords([NewUIPreviewTodayRecord])
    case calm
}

enum NewUIPreviewCapturePhase: Equatable {
    case idle
    case preflight
    case armed
    case canceling
}

enum NewUIPreviewCaptureDirection: Equatable {
    case camera
    case audio
}

@MainActor
final class NewUIPreviewState: ObservableObject {
    @Published var isExpanded = false
    @Published var dockText: String = ""
    @Published var destination: NewUIPreviewDestination = .today
    var namespace: Namespace.ID? = nil

    /// Compatibility for the existing preview dock while destination naming becomes explicit.
    var selectedTab: NewUIPreviewTab {
        get { destination }
        set { destination = newValue }
    }

    @Published var scenario: NewUIPreviewScenario {
        didSet {
            guard oldValue != scenario else { return }
            applyScenario(resetTodaySection: true)
        }
    }

    @Published var selectedTodaySection: NewUIPreviewTodaySection = .records
    @Published var recordsSearchQuery = ""
    @Published var selectedRecordsFilter: NewUIPreviewRecordsFilter = .all
    @Published var selectedRecordsScope: NewUIPreviewRecordsScope = .all
    @Published private(set) var recordsScrollRevision = 0
    @Published var overlay: NewUIPreviewOverlay?

    @Published var hero: NewUIPreviewHero = NewUIPreviewState.calmHero
    /// Up to two due/imminent items not already shown as the Hero.
    @Published var urgentItems: [NewUIPreviewUrgentItem] = []
    /// Up to three actionable todos, shown when the Hero is an execution context.
    @Published var actionableTodos: [NewUIPreviewUrgentItem] = []
    @Published var todayRecords: [NewUIPreviewTodayRecord] = []
    @Published var statistics: NewUIPreviewStatistics = NewUIPreviewStatistics(todayCount: 0, consecutiveDays: 8)

    @Published private(set) var recordFixtures: [NewUIPreviewRecordFixture]

    @Published var captureDirection: NewUIPreviewCaptureDirection?
    @Published var capturePhase: NewUIPreviewCapturePhase = .idle
    @Published var captureDragProgress: CGFloat = 0
    @Published var cameraAffordanceVisible = false
    @Published var captureActionToast: String?

    static let committedThreshold: CGFloat = 0.6
    static let cancelGrace: CGFloat = 0.15
    static let dragThresholdPoints: CGFloat = 140

    private var timer: AnyCancellable?
    private var toastCancellable: AnyCancellable?

    init(
        scenario: NewUIPreviewScenario = .calm,
        recordFixtures: [NewUIPreviewRecordFixture] = NewUIPreviewFixtures.records,
        startsContextTimer: Bool = true
    ) {
        self.scenario = scenario
        self.recordFixtures = recordFixtures
        applyScenario(resetTodaySection: true)
        updateDockText()
        if startsContextTimer {
            startContextTimer()
        }
    }

    func toggle() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0)) {
            isExpanded.toggle()
        }
    }

    func expand() {
        guard !isExpanded else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82, blendDuration: 0)) {
            isExpanded = true
        }
    }

    func collapse() {
        guard isExpanded else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9, blendDuration: 0)) {
            isExpanded = false
        }
    }

    func select(_ tab: NewUIPreviewTab) {
        if tab == .today, destination != .today {
            beginTodayVisit()
        } else {
            destination = tab
        }
    }

    func beginTodayVisit() {
        destination = .today
        selectedTodaySection = hero.context.recommendedTodaySection
    }

    func selectTodaySection(_ section: NewUIPreviewTodaySection) {
        selectedTodaySection = section
    }

    var filteredRecordFixtures: [NewUIPreviewRecordFixture] {
        let scoped = recordFixtures.filter(scopeIncludes)
        let sourceMatches = scoped.filter { selectedRecordsFilter.includes($0.previewSource) }
        return NewUIPreviewFixtures.records(matching: recordsSearchQuery, in: sourceMatches)
    }

    var recordFolderNames: [String] {
        Array(Set(recordFixtures.compactMap(\.folderName)))
            .filter { $0 != FolderTagManager.nottiFolderName }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var recordEventNames: [String] {
        Array(Set(recordFixtures.compactMap(\.eventName)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func selectRecordsScope(_ scope: NewUIPreviewRecordsScope) {
        guard selectedRecordsScope != scope else { return }
        selectedRecordsScope = scope
        recordsScrollRevision += 1
    }

    func updateRecord(_ record: NoteRecord, todos: [String]) {
        guard let index = recordFixtures.firstIndex(where: { $0.id == record.id }) else { return }
        recordFixtures[index].record = record
        recordFixtures[index].todos = todos
        if let todayIndex = todayRecords.firstIndex(where: { $0.id == record.id }) {
            todayRecords[todayIndex] = NewUIPreviewTodayRecord(
                id: record.id,
                title: record.title,
                summary: record.summary,
                thumbnailImageName: recordFixtures[index].media.first?.imageName
            )
        }
    }

    func relatedRecords(for recordID: UUID) -> [NewUIPreviewResolvedRecordRelation] {
        guard let source = recordFixtures.first(where: { $0.id == recordID }) else { return [] }

        return source.relations.compactMap { relation in
            guard relation.recordID != recordID,
                  let fixture = recordFixtures.first(where: { $0.id == relation.recordID }),
                  !fixture.record.isDeleted,
                  !fixture.record.isEncrypted else {
                return nil
            }
            return NewUIPreviewResolvedRecordRelation(fixture: fixture, reason: relation.reason)
        }
        .prefix(3)
        .map { $0 }
    }

    private func scopeIncludes(_ fixture: NewUIPreviewRecordFixture) -> Bool {
        switch selectedRecordsScope {
        case .all:
            return !fixture.record.isDeleted
        case .favorites:
            return !fixture.record.isDeleted && fixture.record.isFavorite
        case .unclassified:
            return !fixture.record.isDeleted && fixture.folderName == nil
        case .today:
            return !fixture.record.isDeleted
                && Calendar.current.isDate(fixture.record.capturedAt, inSameDayAs: NewUIPreviewFixtures.referenceDate)
        case .pending:
            return !fixture.record.isDeleted && fixture.record.processingState == .pending
        case .trash:
            return fixture.record.isDeleted
        case .folder(let name):
            return !fixture.record.isDeleted && fixture.folderName == name
        case .event(let name):
            return !fixture.record.isDeleted && fixture.eventName == name
        }
    }

    func recordFixture(id: UUID) -> NewUIPreviewRecordFixture? {
        recordFixtures.first { $0.id == id }
    }

    func openRecord(_ id: UUID, origin: NewUIPreviewRecordOrigin) {
        guard recordFixture(id: id) != nil else { return }
        overlay = .recordDetail(recordID: id, origin: origin)
    }

    func openModule(_ section: NewUIPreviewTodaySection) {
        overlay = .module(section)
    }

    func dismissOverlay() {
        overlay = nil
    }

    /// Sets Hero, urgent items, review-slot content, and statistics to a self-consistent mock
    /// snapshot for the selected priority tier. Replaces substring-matching over display copy so
    /// every one of the design spec's five Hero states can be previewed directly.
    func applyScenario(resetTodaySection: Bool = false) {
        todayRecords = []
        switch scenario {
        case .activeEvent:
            urgentItems = [
                NewUIPreviewUrgentItem(id: Self.urgentIDs[0], kind: .dueTodo, title: String(localized: "回复设计 review"), detail: String(localized: "截止今晚 22:00"))
            ]
            actionableTodos = [
                NewUIPreviewUrgentItem(id: Self.urgentIDs[0], kind: .dueTodo, title: String(localized: "回复设计 review"), detail: String(localized: "截止今晚 22:00")),
                NewUIPreviewUrgentItem(id: Self.urgentIDs[1], kind: .dueTodo, title: String(localized: "提交产品周报"), detail: String(localized: "今天 18:00 前")),
                NewUIPreviewUrgentItem(id: Self.urgentIDs[2], kind: .imminentEvent, title: String(localized: "和导师的 1:1"), detail: String(localized: "15 分钟后开始"))
            ]
            todayRecords = makeTodayRecords(limit: 1)
            statistics = NewUIPreviewStatistics(todayCount: 1, consecutiveDays: 8)
            hero = NewUIPreviewHero(
                context: .activeEvent,
                title: String(localized: "产品周会"),
                supporting: String(localized: "进行中 · 还剩 25 分钟")
            )
        case .dueTodo:
            urgentItems = [
                NewUIPreviewUrgentItem(id: Self.urgentIDs[2], kind: .imminentEvent, title: String(localized: "和导师的 1:1"), detail: String(localized: "15 分钟后开始"))
            ]
            actionableTodos = [
                NewUIPreviewUrgentItem(id: Self.urgentIDs[1], kind: .dueTodo, title: String(localized: "提交产品周报"), detail: String(localized: "今天 18:00 前")),
                NewUIPreviewUrgentItem(id: Self.urgentIDs[2], kind: .imminentEvent, title: String(localized: "和导师的 1:1"), detail: String(localized: "15 分钟后开始"))
            ]
            todayRecords = makeTodayRecords(limit: 1)
            statistics = NewUIPreviewStatistics(todayCount: 1, consecutiveDays: 8)
            hero = NewUIPreviewHero(context: .dueTodo, title: String(localized: "回复设计 review"), supporting: String(localized: "截止今晚 22:00，还剩不到 2 小时"))
        case .imminentEvent:
            urgentItems = []
            actionableTodos = [
                NewUIPreviewUrgentItem(id: Self.urgentIDs[2], kind: .imminentEvent, title: String(localized: "和导师的 1:1"), detail: String(localized: "15 分钟后开始"))
            ]
            todayRecords = makeTodayRecords(limit: 2)
            statistics = NewUIPreviewStatistics(todayCount: 2, consecutiveDays: 8)
            hero = NewUIPreviewHero(context: .imminentEvent, title: String(localized: "和导师的 1:1"), supporting: String(localized: "15 分钟后开始"))
        case .recordMomentum:
            urgentItems = []
            actionableTodos = []
            todayRecords = makeTodayRecords()
            let todayCount = todayRecords.count
            statistics = NewUIPreviewStatistics(todayCount: todayCount, consecutiveDays: 8)
            hero = NewUIPreviewHero(
                context: .recordMomentum,
                title: String(
                    format: String(localized: "今天已记录 %lld 条"),
                    locale: Locale.current,
                    Int64(todayCount)
                ),
                supporting: String(localized: "继续补充，或问问 Notti")
            )
        case .calm:
            urgentItems = []
            actionableTodos = []
            todayRecords = []
            statistics = NewUIPreviewStatistics(todayCount: 0, consecutiveDays: 8)
            hero = NewUIPreviewState.calmHero
        }
        if resetTodaySection {
            selectedTodaySection = hero.context.recommendedTodaySection
        }
    }

    /// The design spec distinguishes the bounded urgent slot from the adaptive review slot.
    /// The Today view decides how much of the selected review data fits without scrolling.
    var sharedReviewSlot: NewUIPreviewSharedReviewSlot {
        if hero.context.isExecution {
            return .todos(actionableTodos)
        } else if !todayRecords.isEmpty {
            return .todayRecords(todayRecords)
        } else {
            return .calm
        }
    }

    /// Statistics are the first thing to disappear under height pressure (per spec); the view
    /// supplies its measured available height via GeometryReader.
    static let statisticsMinHeight: CGFloat = 680

    func statisticsVisible(availableHeight: CGFloat) -> Bool {
        availableHeight >= NewUIPreviewState.statisticsMinHeight
    }

    var captureGestureEnabled: Bool { !isExpanded && overlay == nil && destination == .today }

    func beginCaptureDrag(direction: NewUIPreviewCaptureDirection) {
        guard captureGestureEnabled, capturePhase == .idle else { return }
        captureDirection = direction
        capturePhase = .preflight
    }

    func updateCaptureDrag(progress: CGFloat) {
        let clamped = min(max(progress, 0), 1)
        captureDragProgress = clamped
        switch capturePhase {
        case .preflight:
            if clamped >= NewUIPreviewState.committedThreshold {
                capturePhase = .armed
                cameraAffordanceVisible = (captureDirection == .camera)
                triggerLightHaptic()
            }
        case .armed:
            if clamped < NewUIPreviewState.committedThreshold - NewUIPreviewState.cancelGrace {
                cancelCapture()
            }
        default:
            break
        }
    }

    func endCaptureDrag() {
        switch (capturePhase, captureDirection) {
        case (.armed, .camera):
            openCamera()
            resetCapture()
        case (.armed, .audio):
            openAudioEntry()
            resetCapture()
        default:
            cancelCapture()
        }
    }

    func cancelCapture() {
        guard capturePhase != .idle, capturePhase != .canceling else { return }
        capturePhase = .canceling
        cameraAffordanceVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            if self.capturePhase == .canceling {
                self.resetCapture()
            }
        }
    }

    private func resetCapture() {
        capturePhase = .idle
        captureDirection = nil
        captureDragProgress = 0
        cameraAffordanceVisible = false
    }

    private func openCamera() {
        showCaptureToast(String(localized: "📷 已打开相机（预览）"))
    }

    private func openAudioEntry() {
        showCaptureToast(String(localized: "🎙 已打开音频入口（预览）"))
    }

    private func showCaptureToast(_ text: String) {
        captureActionToast = text
        toastCancellable = Timer.publish(every: 1.8, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.captureActionToast = nil
            }
    }

    private func triggerLightHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func updateDockText() {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 21 {
            dockText = String(localized: "✨ 今天过得怎么样？")
        } else if statistics.todayCount > 0 {
            dockText = String(localized: "✨ 已记录 \(statistics.todayCount) 条拍记")
        } else if statistics.consecutiveDays > 1 {
            dockText = String(localized: "✨ 已陪伴你第 \(statistics.consecutiveDays) 天")
        } else {
            dockText = String(localized: "✨ 今天想记录什么？")
        }
    }

    private func startContextTimer() {
        timer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateDockText()
            }
    }

    static let calmHero = NewUIPreviewHero(context: .calm,
                                           title: String(localized: "此刻很安静"),
                                           supporting: String(localized: "下拉拍一张，或上拉录一段"))

    private func makeTodayRecords(limit: Int? = nil) -> [NewUIPreviewTodayRecord] {
        let safeFixtures = recordFixtures.filter { !$0.record.isEncrypted && !$0.record.isDeleted }
        let selectedFixtures = limit.map { Array(safeFixtures.prefix($0)) } ?? safeFixtures

        return selectedFixtures.map {
            NewUIPreviewTodayRecord(
                id: $0.id,
                title: $0.record.title,
                summary: $0.cardSummary,
                thumbnailImageName: $0.media.first?.imageName
            )
        }
    }

    private static let urgentIDs: [UUID] = [
        UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
        UUID(uuidString: "30000000-0000-0000-0000-000000000003")!
    ]
}
