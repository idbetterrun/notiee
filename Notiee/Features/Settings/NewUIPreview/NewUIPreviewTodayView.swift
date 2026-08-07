import SwiftUI

enum NewUIPreviewTodayLayout {
    static let eyebrowTitle = "Today"
    static let itemHeight: CGFloat = 68
    static let itemSpacing: CGFloat = 12
    static let topPadding: CGFloat = 20
    static let heroToSectionSpacing: CGFloat = 24
    static let sectionSpacing: CGFloat = 14
    static let viewAllHeight: CGFloat = 44
    static let dockReservedHeight: CGFloat = 104

    static func fittingItemCount(
        availableHeight: CGFloat,
        fixedContentHeight: CGFloat,
        itemCount: Int
    ) -> Int {
        guard itemCount > 0 else { return 0 }

        let rowBudget = max(availableHeight - fixedContentHeight, 0)
        let completeRows = Int(
            floor((rowBudget + itemSpacing) / (itemHeight + itemSpacing))
        )
        return min(itemCount, max(1, completeRows))
    }
}

struct NewUIPreviewTodayView: View {
    @EnvironmentObject private var nottiState: NewUIPreviewState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.newUIPreviewBackground.ignoresSafeArea()

            if nottiState.hero.context.showsAurora {
                VStack(spacing: 0) {
                    NewUIPreviewAuroraBackdrop(
                        colorHex: NewUIPreviewBrand.accentHex,
                        isActive: nottiState.destination == .today
                    )
                        .frame(height: 300)
                        .opacity(colorScheme == .dark ? 0.48 : 0.68)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            }

            GeometryReader { proxy in
                NewUIPreviewDashboardContent(
                    availableHeight: max(
                        proxy.size.height - NewUIPreviewTodayLayout.dockReservedHeight,
                        0
                    )
                )
                    .environmentObject(nottiState)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.bottom, NewUIPreviewTodayLayout.dockReservedHeight)
                    .contentShape(Rectangle())
                    .simultaneousGesture(captureGesture, including: .gesture)
            }

            captureFeedback
                .allowsHitTesting(false)
        }
    }

    private var captureGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width),
                      nottiState.captureGestureEnabled else { return }
                if nottiState.capturePhase == .idle {
                    nottiState.beginCaptureDrag(direction: value.translation.height > 0 ? .camera : .audio)
                }
                nottiState.updateCaptureDrag(
                    progress: abs(value.translation.height) / NewUIPreviewState.dragThresholdPoints
                )
            }
            .onEnded { _ in
                guard nottiState.capturePhase != .idle else { return }
                nottiState.endCaptureDrag()
            }
    }

    @ViewBuilder
    private var captureFeedback: some View {
        if nottiState.cameraAffordanceVisible, nottiState.captureDirection == .camera {
            NewUIPreviewCameraAffordance()
                .transition(.scale.combined(with: .opacity))
        }

        VStack {
            if nottiState.captureDirection == .camera, nottiState.capturePhase != .idle {
                CapturePullIndicator(progress: nottiState.captureDragProgress, direction: .camera)
                    .padding(.top, 8)
            }
            Spacer()
            if nottiState.captureDirection == .audio, nottiState.capturePhase != .idle {
                CapturePullIndicator(progress: nottiState.captureDragProgress, direction: .audio)
                    .padding(.bottom, 112)
            }
        }

        if let toast = nottiState.captureActionToast {
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
    @EnvironmentObject private var nottiState: NewUIPreviewState

    let availableHeight: CGFloat

    @State private var measuredHeroHeight: CGFloat = 92
    @State private var measuredTodayHeaderHeight: CGFloat = 97

    var body: some View {
        VStack(alignment: .leading, spacing: NewUIPreviewTodayLayout.heroToSectionSpacing) {
            hero
            todaySection
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, NewUIPreviewTodayLayout.topPadding)
        .animation(.easeInOut(duration: 0.22), value: nottiState.hero.context)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: NewUIPreviewTodayLayout.eyebrowTitle)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.newUIPreviewSecondary)
                .lineLimit(1)

            Text(nottiState.hero.title)
                .font(.system(size: 31, weight: .bold))
                .foregroundStyle(Color.newUIPreviewPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(nottiState.hero.supporting)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.newUIPreviewSecondary)
                .lineLimit(2)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            scheduleMeasuredHeight(height, target: $measuredHeroHeight)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: NewUIPreviewTodayLayout.sectionSpacing) {
            todayHeader

            todayRows

            NewUIPreviewViewAllButton(
                section: nottiState.selectedTodaySection,
                action: openFullSection
            )
        }
    }

    private var todayHeader: some View {
        VStack(alignment: .leading, spacing: NewUIPreviewTodayLayout.sectionSpacing) {
            Text("今天")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Color.newUIPreviewPrimary)

            NewUIPreviewTodaySelector(selection: nottiState.selectedTodaySection) { section in
                nottiState.selectTodaySection(section)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            scheduleMeasuredHeight(height, target: $measuredTodayHeaderHeight)
        }
    }

    @ViewBuilder
    private var todayRows: some View {
        VStack(alignment: .leading, spacing: NewUIPreviewTodayLayout.itemSpacing) {
            switch nottiState.selectedTodaySection {
            case .records:
                if nottiState.todayRecords.isEmpty {
                    emptyRow("今天还没有新记录。")
                } else {
                    ForEach(nottiState.todayRecords.prefix(visibleItemCount)) { record in
                        Button {
                            nottiState.openRecord(record.id, origin: .today)
                        } label: {
                            NewUIPreviewTodayItemCard(
                                title: record.title,
                                detail: record.summary,
                                style: .record(imageName: record.thumbnailImageName),
                                recordID: record.id,
                                transitionOrigin: .today,
                                transitionNamespace: nottiState.namespace
                            )
                        }
                        .buttonStyle(NewUIPreviewPressStyle())
                    }
                }
            case .todos:
                if nottiState.actionableTodos.isEmpty {
                    emptyRow("今天没有待处理事项。")
                } else {
                    ForEach(nottiState.actionableTodos.prefix(visibleItemCount)) { item in
                        Button { nottiState.openModule(.todos) } label: {
                            NewUIPreviewTodayItemCard(
                                title: item.title,
                                detail: item.detail,
                                style: .todo
                            )
                        }
                        .buttonStyle(NewUIPreviewPressStyle())
                    }
                }
            case .schedule:
                if scheduleItems.isEmpty {
                    emptyRow("今天没有日程安排。")
                } else {
                    ForEach(scheduleItems.prefix(visibleItemCount)) { item in
                        Button { nottiState.openModule(.schedule) } label: {
                            NewUIPreviewTodayItemCard(
                                title: item.title,
                                detail: item.detail,
                                style: .schedule(isNow: item.kind == .activeEvent)
                            )
                        }
                        .buttonStyle(NewUIPreviewPressStyle())
                    }
                }
            }
        }
        .id(nottiState.selectedTodaySection)
        .transition(.opacity)
    }

    private func emptyRow(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.newUIPreviewSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: NewUIPreviewTodayLayout.itemHeight)
    }

    private var fixedContentHeight: CGFloat {
        NewUIPreviewTodayLayout.topPadding
            + measuredHeroHeight
            + NewUIPreviewTodayLayout.heroToSectionSpacing
            + measuredTodayHeaderHeight
            + NewUIPreviewTodayLayout.sectionSpacing * 2
            + NewUIPreviewTodayLayout.viewAllHeight
    }

    private var visibleItemCount: Int {
        NewUIPreviewTodayLayout.fittingItemCount(
            availableHeight: availableHeight,
            fixedContentHeight: fixedContentHeight,
            itemCount: selectedItemCount
        )
    }

    private var selectedItemCount: Int {
        switch nottiState.selectedTodaySection {
        case .records: return nottiState.todayRecords.count
        case .todos: return nottiState.actionableTodos.count
        case .schedule: return scheduleItems.count
        }
    }

    private func openFullSection() {
        switch nottiState.selectedTodaySection {
        case .records:
            nottiState.select(.records)
        case .todos:
            nottiState.openModule(.todos)
        case .schedule:
            nottiState.openModule(.schedule)
        }
    }

    private func scheduleMeasuredHeight(_ height: CGFloat, target: Binding<CGFloat>) {
        guard height > 0, abs(target.wrappedValue - height) > 0.5 else { return }
        DispatchQueue.main.async {
            guard abs(target.wrappedValue - height) > 0.5 else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                target.wrappedValue = height
            }
        }
    }

    private var scheduleItems: [NewUIPreviewUrgentItem] {
        var items = nottiState.urgentItems.filter { $0.kind != .dueTodo }
        if nottiState.hero.context == .activeEvent || nottiState.hero.context == .imminentEvent {
            items.insert(
                NewUIPreviewUrgentItem(
                    id: UUID(uuidString: "30000000-0000-0000-0000-000000000099")!,
                    kind: nottiState.hero.context == .activeEvent ? .activeEvent : .imminentEvent,
                    title: nottiState.hero.title,
                    detail: nottiState.hero.supporting
                ),
                at: 0
            )
        }
        return items
    }
}

struct NewUIPreviewViewAllButton: View {
    let section: NewUIPreviewTodaySection
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: section.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                Text(section.viewAllTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(section.tint)
            .padding(.horizontal, 16)
            .frame(height: NewUIPreviewTodayLayout.viewAllHeight)
            .background(pillBacking, in: Capsule())
            .contentShape(Capsule())
            .newUIPreviewGlass(in: Capsule())
        }
        .buttonStyle(NewUIPreviewPressStyle())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHint("打开完整列表")
    }

    private var pillBacking: Color {
        if reduceTransparency {
            return Color(uiColor: .secondarySystemBackground)
        }
        return Color.white.opacity(colorScheme == .dark ? 0.10 : 0.42)
    }
}

private struct NewUIPreviewTodaySelector: View {
    let selection: NewUIPreviewTodaySection
    let onSelect: (NewUIPreviewTodaySection) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(NewUIPreviewTodaySection.allCases) { section in
                categoryButton(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
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

enum NewUIPreviewTodayItemStyle: Equatable {
    case record(imageName: String?)
    case todo
    case schedule(isNow: Bool)
}

struct NewUIPreviewTodayItemCard: View {
    let title: String
    let detail: String
    let style: NewUIPreviewTodayItemStyle
    var recordID: UUID? = nil
    var transitionOrigin: NewUIPreviewRecordOrigin? = nil
    var transitionNamespace: Namespace.ID? = nil

    var body: some View {
        HStack(spacing: 12) {
            leadingVisual

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.newUIPreviewPrimary)
                    .lineLimit(1)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.newUIPreviewSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: NewUIPreviewTodayLayout.itemHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .newUIPreviewRecordTransitionSurface(
                    recordID: recordID,
                    origin: transitionOrigin,
                    namespace: transitionNamespace,
                    isSource: true
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var leadingVisual: some View {
        switch style {
        case .record(let imageName):
            if let imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                iconTile(symbol: "note.text", tint: .newUIPreviewAccent)
            }
        case .todo:
            iconTile(symbol: "circle", tint: .orange)
        case .schedule(let isNow):
            VStack(spacing: 2) {
                Image(systemName: isNow ? "play.fill" : "calendar")
                    .font(.system(size: 13, weight: .bold))
                Text(isNow ? "现在" : "稍后")
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.blue)
            .frame(width: 44, height: 44)
            .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
        }
    }

    private func iconTile(symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}

private extension NewUIPreviewTodaySection {
    var viewAllTitle: LocalizedStringKey {
        switch self {
        case .records: return "查看全部记录"
        case .todos: return "查看全部待办"
        case .schedule: return "查看全部日程"
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
