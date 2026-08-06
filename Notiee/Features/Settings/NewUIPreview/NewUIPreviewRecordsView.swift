import SwiftUI

struct NewUIPreviewRecordsView: View {
    @EnvironmentObject private var previewState: NewUIPreviewState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let horizontalPadding: CGFloat = 16
    private let columnSpacing: CGFloat = 12
    private let topAnchor = "new-ui-preview-records-top"

    private var columnCount: Int {
        dynamicTypeSize.isAccessibilitySize ? 1 : 2
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = max(proxy.size.width - horizontalPadding * 2, 0)
            let columnWidth = NewUIPreviewMasonryGeometry.columnWidth(
                containerWidth: contentWidth,
                columns: columnCount,
                spacing: columnSpacing
            )

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Color.clear
                            .frame(height: 1)
                            .id(topAnchor)

                        Section {
                            recordsContent(
                                contentWidth: contentWidth,
                                columnWidth: columnWidth
                            )
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 12)
                            .padding(.bottom, 124)
                        } header: {
                            searchHeader(scrollProxy: scrollProxy)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Color.newUIPreviewBackground)
        .accessibilityIdentifier("new-ui-preview-records")
    }

    @ViewBuilder
    private func recordsContent(contentWidth: CGFloat, columnWidth: CGFloat) -> some View {
        if previewState.filteredRecordFixtures.isEmpty {
            emptyState
                .frame(width: contentWidth)
        } else {
            NewUIPreviewMasonryLayout(columns: columnCount, spacing: columnSpacing) {
                ForEach(previewState.filteredRecordFixtures) { fixture in
                    NewUIPreviewRecordCard(
                        fixture: fixture,
                        cardWidth: columnWidth,
                        transitionOrigin: .records,
                        transitionNamespace: previewState.namespace
                    ) {
                        previewState.openRecord(fixture.id, origin: .records)
                    }
                }
            }
            .frame(width: contentWidth, alignment: .leading)
        }
    }

    private func searchHeader(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            searchField

            NewUIPreviewRecordsFilterPicker(
                selection: previewState.selectedRecordsFilter
            ) { filter in
                guard previewState.selectedRecordsFilter != filter else { return }
                previewState.selectedRecordsFilter = filter
                withAnimation(.snappy(duration: 0.32, extraBounce: 0)) {
                    scrollProxy.scrollTo(topAnchor, anchor: .top)
                }
            }
        }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .zIndex(1)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.newUIPreviewSecondary)
                .accessibilityHidden(true)

            TextField("搜索标题和摘要", text: $previewState.recordsSearchQuery)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)

            if !previewState.recordsSearchQuery.isEmpty {
                Button {
                    previewState.recordsSearchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.newUIPreviewSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, previewState.recordsSearchQuery.isEmpty ? 16 : 4)
        .frame(minHeight: 52)
        .contentShape(Capsule())
        .newUIPreviewGlass(in: Capsule(), interactive: true)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: previewState.recordsSearchQuery.isEmpty ? "tray" : "magnifyingglass")
                .font(.title2)
                .foregroundStyle(Color.newUIPreviewSecondary)
                .accessibilityHidden(true)

            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(Color.newUIPreviewPrimary)

            if !previewState.recordsSearchQuery.isEmpty {
                Text("尝试搜索标题或摘要中的其他词语")
                    .font(.subheadline)
                    .foregroundStyle(Color.newUIPreviewSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
        .padding(.horizontal, 24)
    }

    private var emptyStateTitle: LocalizedStringKey {
        if !previewState.recordsSearchQuery.isEmpty {
            return "没有匹配的记录"
        }
        if previewState.selectedRecordsFilter != .all {
            return "此分类还没有记录"
        }
        return "还没有记录"
    }
}

struct NewUIPreviewRecordsFilterPicker: View {
    let selection: NewUIPreviewRecordsFilter
    let onSelect: (NewUIPreviewRecordsFilter) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(NewUIPreviewRecordsFilter.allCases) { filter in
                        filterButton(filter)
                            .id(filter.id)
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
            .onChange(of: selection) { _, newSelection in
                withAnimation(.snappy(duration: 0.35, extraBounce: 0.08)) {
                    proxy.scrollTo(newSelection.id, anchor: .center)
                }
            }
        }
        .frame(height: 48)
    }

    private func filterButton(_ filter: NewUIPreviewRecordsFilter) -> some View {
        let isSelected = selection == filter

        return Button {
            withAnimation(.snappy(duration: 0.35, extraBounce: 0.08)) {
                onSelect(filter)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 16, weight: .semibold))

                if isSelected {
                    Text(filter.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .foregroundStyle(isSelected ? Color.white : filter.tint)
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, isSelected ? 14 : 0)
            .background { filterBackground(filter, isSelected: isSelected) }
            .contentShape(Capsule())
            .animation(.snappy(duration: 0.35, extraBounce: 0.08), value: isSelected)
        }
        .buttonStyle(NewUIPreviewPressStyle())
        .accessibilityLabel(Text(filter.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func filterBackground(
        _ filter: NewUIPreviewRecordsFilter,
        isSelected: Bool
    ) -> some View {
        let maskOpacity = NewUIPreviewRecordsFilterAppearance.whiteMaskOpacity(
            isSelected: isSelected,
            colorScheme: colorScheme,
            reduceTransparency: reduceTransparency
        )

        return ZStack {
            Capsule().fill(
                isSelected
                    ? filter.tint
                    : Color(
                        uiColor: reduceTransparency
                            ? .secondarySystemBackground
                            : .secondarySystemFill
                    )
            )

            if maskOpacity > 0 {
                Capsule()
                    .fill(Color.white.opacity(maskOpacity))
                    .allowsHitTesting(false)
            }
        }
    }
}

enum NewUIPreviewRecordsFilterAppearance {
    static func whiteMaskOpacity(
        isSelected: Bool,
        colorScheme: ColorScheme,
        reduceTransparency: Bool
    ) -> Double {
        guard !isSelected else { return 0 }
        if reduceTransparency {
            return colorScheme == .dark ? 0.20 : 0.70
        }
        return colorScheme == .dark ? 0.12 : 0.46
    }
}

private extension NewUIPreviewRecordsFilter {
    var title: LocalizedStringKey {
        switch self {
        case .all: return "全部"
        case .photo: return "照片"
        case .audio: return "录音"
        case .text: return "文字"
        case .notti: return "来自 Notti"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .photo: return "photo"
        case .audio: return "waveform"
        case .text: return "doc.text"
        case .notti: return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .all: return .newUIPreviewAccent
        case .photo: return .blue
        case .audio: return .red
        case .text: return .indigo
        case .notti: return .purple
        }
    }
}
