import SwiftUI

struct NewUIPreviewTodayView: View {
    @EnvironmentObject private var sparkState: NewUIPreviewState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.newUIPreviewBackground.ignoresSafeArea()

            if sparkState.hero.context == .activeEvent {
                VStack(spacing: 0) {
                    NewUIPreviewAuroraBackdrop(colorHex: sparkState.hero.auroraColorHex)
                        .frame(height: 300)
                        .opacity(colorScheme == .dark ? 0.62 : 0.78)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }

            NewUIPreviewDashboardContent()
                .environmentObject(sparkState)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.bottom, 104)
                .contentShape(Rectangle())
                .simultaneousGesture(captureGesture, including: .gesture)

            captureFeedback
                .allowsHitTesting(false)

            NewUIPreviewDockBar()
        }
    }

    private var captureGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width),
                      sparkState.captureGestureEnabled else { return }
                if sparkState.capturePhase == .idle {
                    sparkState.beginCaptureDrag(direction: value.translation.height > 0 ? .camera : .audio)
                }
                sparkState.updateCaptureDrag(
                    progress: abs(value.translation.height) / NewUIPreviewState.dragThresholdPoints
                )
            }
            .onEnded { _ in
                guard sparkState.capturePhase != .idle else { return }
                sparkState.endCaptureDrag()
            }
    }

    @ViewBuilder
    private var captureFeedback: some View {
        if sparkState.cameraAffordanceVisible, sparkState.captureDirection == .camera {
            NewUIPreviewCameraAffordance()
                .transition(.scale.combined(with: .opacity))
        }

        VStack {
            if sparkState.captureDirection == .camera, sparkState.capturePhase != .idle {
                CapturePullIndicator(progress: sparkState.captureDragProgress, direction: .camera)
                    .padding(.top, 8)
            }
            Spacer()
            if sparkState.captureDirection == .audio, sparkState.capturePhase != .idle {
                CapturePullIndicator(progress: sparkState.captureDragProgress, direction: .audio)
                    .padding(.bottom, 112)
            }
        }

        if let toast = sparkState.captureActionToast {
            Text(toast)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

private struct NewUIPreviewDashboardContent: View {
    @EnvironmentObject private var sparkState: NewUIPreviewState

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            hero
            shortcuts
            todaySection
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .animation(.easeInOut(duration: 0.22), value: sparkState.hero.context)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sparkState.hero.title)
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(Color.newUIPreviewPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(sparkState.hero.supporting)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.newUIPreviewSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var shortcuts: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            NewUIPreviewGlassContainer {
                HStack(spacing: 8) {
                    shortcut(section: .records, symbol: "books.vertical.fill", count: sparkState.recordFixtures.count)
                    shortcut(section: .todos, symbol: "checkmark.circle.fill", count: sparkState.actionableTodos.count)
                    shortcut(section: .schedule, symbol: "calendar", count: scheduleItems.count)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func shortcut(section: NewUIPreviewTodaySection, symbol: String, count: Int) -> some View {
        Button {
            if section == .records {
                sparkState.select(.records)
            } else {
                sparkState.openModule(section)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(section.tint)
                Text(section.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.newUIPreviewPrimary)
                    .lineLimit(1)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(section.tint)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(section.tint.opacity(0.13), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Capsule())
            .background(Color(uiColor: .secondarySystemFill), in: Capsule())
            .newUIPreviewGlass(in: Capsule(), interactive: true)
        }
        .buttonStyle(NewUIPreviewPressStyle())
        .accessibilityLabel(Text(section.title))
        .accessibilityValue(Text("\(count)"))
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今天")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.newUIPreviewPrimary)

            NewUIPreviewTodaySelector(selection: sparkState.selectedTodaySection) { section in
                sparkState.selectTodaySection(section)
            }

            todayRows
        }
    }

    @ViewBuilder
    private var todayRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch sparkState.selectedTodaySection {
            case .records:
                if sparkState.todayRecords.isEmpty {
                    emptyRow("今天还没有新记录。")
                } else {
                    ForEach(sparkState.todayRecords.prefix(3)) { record in
                        Button { sparkState.openRecord(record.id) } label: {
                            NewUIPreviewTodayRecordRow(record: record)
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .todos:
                if sparkState.actionableTodos.isEmpty {
                    emptyRow("今天没有待处理事项。")
                } else {
                    ForEach(sparkState.actionableTodos.prefix(3)) { item in
                        NewUIPreviewTodoRow(item: item)
                    }
                }
            case .schedule:
                if scheduleItems.isEmpty {
                    emptyRow("今天没有日程安排。")
                } else {
                    ForEach(scheduleItems.prefix(3)) { item in
                        NewUIPreviewScheduleRow(item: item)
                    }
                }
            }
        }
    }

    private func emptyRow(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.newUIPreviewSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    private var scheduleItems: [NewUIPreviewUrgentItem] {
        var items = sparkState.urgentItems.filter { $0.kind != .dueTodo }
        if sparkState.hero.context == .activeEvent || sparkState.hero.context == .imminentEvent {
            items.insert(
                NewUIPreviewUrgentItem(
                    id: UUID(uuidString: "30000000-0000-0000-0000-000000000099")!,
                    kind: sparkState.hero.context == .activeEvent ? .activeEvent : .imminentEvent,
                    title: sparkState.hero.title,
                    detail: sparkState.hero.supporting
                ),
                at: 0
            )
        }
        return items
    }
}

private struct NewUIPreviewTodaySelector: View {
    let selection: NewUIPreviewTodaySection
    let onSelect: (NewUIPreviewTodaySection) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(NewUIPreviewTodaySection.allCases) { section in
                        categoryButton(section)
                            .id(section.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                proxy.scrollTo(selection.id, anchor: .center)
            }
            .onChange(of: selection) { _, newSelection in
                withAnimation(.snappy(duration: 0.35, extraBounce: 0.08)) {
                    proxy.scrollTo(newSelection.id, anchor: .center)
                }
            }
        }
    }

    private func categoryButton(_ section: NewUIPreviewTodaySection) -> some View {
        let isSelected = selection == section

        return Button {
            withAnimation(.snappy(duration: 0.35, extraBounce: 0.08)) {
                onSelect(section)
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 18, weight: .semibold))

                if isSelected {
                    Text(section.title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.9)),
                                removal: .opacity
                            )
                        )
                }
            }
            .foregroundStyle(isSelected ? Color.white : section.tint)
            .frame(minWidth: isSelected ? 0 : 52, minHeight: 52)
            .padding(.horizontal, isSelected ? 18 : 0)
            .background(
                Capsule()
                    .fill(isSelected ? section.tint : Color(uiColor: .secondarySystemFill))
            )
            .contentShape(Capsule())
            .animation(.snappy(duration: 0.35, extraBounce: 0.08), value: isSelected)
        }
        .buttonStyle(NewUIPreviewPressStyle())
        .accessibilityLabel(Text(section.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct NewUIPreviewTodoRow: View {
    let item: NewUIPreviewUrgentItem

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewAccent)
            rowText
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(item.detail).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.newUIPreviewSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NewUIPreviewScheduleRow: View {
    let item: NewUIPreviewUrgentItem

    var body: some View {
        HStack(spacing: 12) {
            Text(item.kind == .activeEvent ? "现在" : "稍后")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.newUIPreviewAccent)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(item.detail).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.newUIPreviewSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

struct NewUIPreviewTodayRecordRow: View {
    let record: NewUIPreviewTodayRecord

    var body: some View {
        HStack(spacing: 11) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(record.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if !record.summary.isEmpty {
                    Text(record.summary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.newUIPreviewSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewSecondary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let imageName = record.thumbnailImageName {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "note.text")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewAccent)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)
        }
    }
}

private struct NewUIPreviewCameraAffordance: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewAccent)
            Text("松开打开相机")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewPrimary)
        }
        .frame(width: 120, height: 120)
        .background(Circle().fill(Color.newUIPreviewBackground.opacity(0.94)))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
    }
}

struct CapturePullIndicator: View {
    let progress: CGFloat
    let direction: NewUIPreviewCaptureDirection

    var body: some View {
        let clamped = min(1, max(0, progress))
        ZStack {
            Circle().stroke(Color.newUIPreviewPrimary.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Color.newUIPreviewAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: direction == .camera ? "camera.fill" : "mic.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewAccent)
        }
        .frame(width: 44, height: 44)
        .background(Circle().fill(Color.newUIPreviewBackground.opacity(0.9)))
        .scaleEffect(0.9 + 0.1 * clamped)
    }
}

extension NewUIPreviewTodaySection {
    var title: LocalizedStringKey {
        switch self {
        case .records: return "记录"
        case .todos: return "待办"
        case .schedule: return "日程"
        }
    }

    var symbolName: String {
        switch self {
        case .records: return "note.text"
        case .todos: return "checklist"
        case .schedule: return "calendar"
        }
    }

    var tint: Color {
        switch self {
        case .records: return .newUIPreviewAccent
        case .todos: return .orange
        case .schedule: return .blue
        }
    }
}
