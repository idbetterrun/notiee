import SwiftUI

struct NewUIPreviewRootView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var nottiState = NewUIPreviewState()
    @Namespace private var nottiNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.newUIPreviewBackground.ignoresSafeArea()

            destinationPages
                .scaleEffect(
                    !hasModuleOverlay || reduceMotion ? 1 : 0.985,
                    anchor: .center
                )
                .offset(x: !hasModuleOverlay || reduceMotion ? 0 : -12)

            if nottiState.overlay == nil {
                NewUIPreviewDockBar()
                    .allowsHitTesting(!nottiState.isExpanded)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if nottiState.isExpanded {
                NewUIPreviewComposerView()
                    .environmentObject(nottiState)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(2)
            }

            overlay
                .zIndex(3)
        }
        .animation(pageAnimation, value: nottiState.destination)
        .animation(overlayAnimation, value: nottiState.overlay)
        .environmentObject(nottiState)
        .navigationBarBackButtonHidden(true)
        .navigationTitle(recordsNavigationIsActive ? String(localized: "记录") : "")
        .navigationBarTitleDisplayMode(recordsNavigationIsActive ? .large : .inline)
        .toolbarBackground(
            nottiState.destination == .records && nottiState.overlay == nil ? .visible : .hidden,
            for: .navigationBar
        )
        .toolbar(nottiState.overlay == nil ? .visible : .hidden, for: .navigationBar)
        .toolbar { labToolbar }
        .onAppear { nottiState.namespace = nottiNamespace }
    }

    private var destinationPages: some View {
        ZStack {
            NewUIPreviewTodayView()
                .opacity(pageIsVisible(.today) ? 1 : 0)
                .offset(x: pageOffset(for: .today))
                .allowsHitTesting(nottiState.destination == .today && nottiState.overlay == nil)
                .accessibilityHidden(nottiState.destination != .today || nottiState.overlay != nil)
                .zIndex(nottiState.destination == .today ? 1 : 0)

            NewUIPreviewRecordsView()
                .opacity(pageIsVisible(.records) ? 1 : 0)
                .offset(x: pageOffset(for: .records))
                .allowsHitTesting(nottiState.destination == .records && nottiState.overlay == nil)
                .accessibilityHidden(nottiState.destination != .records || nottiState.overlay != nil)
                .zIndex(nottiState.destination == .records ? 1 : 0)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch nottiState.overlay {
        case .module(let section):
            NewUIPreviewModuleView(section: section) {
                nottiState.dismissOverlay()
            }
            .transition(childPageTransition)
        case .recordDetail(let recordID, let origin):
            if let fixture = nottiState.recordFixture(id: recordID) {
                NewUIPreviewRecordDetailView(
                    fixture: fixture,
                    transitionOrigin: origin,
                    transitionNamespace: reduceMotion ? nil : nottiNamespace
                ) {
                    nottiState.dismissOverlay()
                }
                .transition(.opacity)
            }
        case nil:
            EmptyView()
        }
    }

    private var recordsNavigationIsActive: Bool {
        nottiState.destination == .records && nottiState.overlay == nil
    }

    private var hasModuleOverlay: Bool {
        guard case .module = nottiState.overlay else { return false }
        return true
    }

    private var hasRecordDetailOverlay: Bool {
        guard case .recordDetail = nottiState.overlay else { return false }
        return true
    }

    private func pageIsVisible(_ destination: NewUIPreviewDestination) -> Bool {
        nottiState.destination == destination && !hasRecordDetailOverlay
    }

    private var pageAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .snappy(duration: 0.32, extraBounce: 0)
    }

    private var overlayAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .snappy(duration: 0.38, extraBounce: 0.02)
    }

    private var childPageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .trailing).combined(with: .opacity)
    }

    private func pageOffset(for destination: NewUIPreviewDestination) -> CGFloat {
        guard !reduceMotion else { return 0 }
        switch (destination, nottiState.destination) {
        case (.today, .today), (.records, .records): return 0
        case (.today, .records): return -18
        case (.records, .today): return 18
        }
    }

    @ToolbarContentBuilder
    private var labToolbar: some ToolbarContent {
        if nottiState.overlay == nil {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button {
                        dismiss()
                    } label: {
                        Label("退出预览", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.newUIPreviewPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("菜单")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(NewUIPreviewScenario.allCases) { scenario in
                        Button {
                            nottiState.scenario = scenario
                        } label: {
                            if nottiState.scenario == scenario {
                                Label(scenario.label, systemImage: "checkmark")
                            } else {
                                Text(scenario.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "theatermasks")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.newUIPreviewPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("场景切换")
            }
        }
    }
}

private struct NewUIPreviewModuleView: View {
    @EnvironmentObject private var state: NewUIPreviewState

    let section: NewUIPreviewTodaySection
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.newUIPreviewBackground.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Text(section.fullModuleTitle)
                        .font(.system(size: 34, weight: .bold))
                        .padding(.bottom, 8)
                    moduleContent
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .newUIPreviewGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(NewUIPreviewPressStyle())
                .accessibilityLabel("返回")
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color.newUIPreviewBackground.opacity(0.92))
        }
    }

    @ViewBuilder
    private var moduleContent: some View {
        switch section {
        case .records:
            EmptyView()
        case .todos:
            ForEach(allTodoItems) { item in
                moduleRow(symbol: "circle", title: item.title, detail: item.detail)
            }
            moduleRow(symbol: "circle", title: String(localized: "整理下周计划"), detail: String(localized: "明天"))
            moduleRow(symbol: "checkmark.circle.fill", title: String(localized: "确认演示设备"), detail: String(localized: "已完成"))
        case .schedule:
            moduleRow(symbol: "video.fill", title: String(localized: "产品周会"), detail: "10:00 - 10:45")
            moduleRow(symbol: "person.2.fill", title: String(localized: "和导师的 1:1"), detail: "14:30 - 15:00")
            moduleRow(symbol: "figure.walk", title: String(localized: "晚间散步"), detail: "19:20 - 19:50")
        }
    }

    private var allTodoItems: [NewUIPreviewUrgentItem] {
        var seen = Set<UUID>()
        return (state.actionableTodos + state.urgentItems.filter { $0.kind == .dueTodo })
            .filter { seen.insert($0.id).inserted }
    }

    private func moduleRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(Color.newUIPreviewSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

private extension NewUIPreviewTodaySection {
    var fullModuleTitle: LocalizedStringKey {
        switch self {
        case .records: return "全部记录"
        case .todos: return "全部待办"
        case .schedule: return "全部日程"
        }
    }
}
