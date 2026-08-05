import SwiftUI

struct NewUIPreviewRootView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sparkState = NewUIPreviewState()
    @Namespace private var sparkNamespace

    var body: some View {
        ZStack {
            Color.newUIPreviewBackground.ignoresSafeArea()

            destination

            if sparkState.isExpanded {
                NewUIPreviewComposerView()
                    .environmentObject(sparkState)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(2)
            }

            overlay
                .zIndex(3)
        }
        .environmentObject(sparkState)
        .navigationBarBackButtonHidden(true)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            sparkState.destination == .records && sparkState.overlay == nil ? .visible : .hidden,
            for: .navigationBar
        )
        .toolbar(sparkState.overlay == nil ? .visible : .hidden, for: .navigationBar)
        .toolbar { labToolbar }
        .onAppear { sparkState.namespace = sparkNamespace }
    }

    @ViewBuilder
    private var destination: some View {
        switch sparkState.destination {
        case .today:
            NewUIPreviewTodayView()
        case .records:
            ZStack(alignment: .bottom) {
                NewUIPreviewRecordsView()
                NewUIPreviewDockBar()
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch sparkState.overlay {
        case .module(let section):
            NewUIPreviewModuleView(section: section) {
                sparkState.dismissOverlay()
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .recordDetail(let recordID):
            if let fixture = sparkState.recordFixture(id: recordID) {
                NewUIPreviewRecordDetailView(fixture: fixture) {
                    sparkState.dismissOverlay()
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        case nil:
            EmptyView()
        }
    }

    @ToolbarContentBuilder
    private var labToolbar: some ToolbarContent {
        if sparkState.overlay == nil {
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
                            sparkState.scenario = scenario
                        } label: {
                            if sparkState.scenario == scenario {
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
