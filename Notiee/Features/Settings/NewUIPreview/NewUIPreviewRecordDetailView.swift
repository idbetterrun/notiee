import Foundation
import SwiftUI
import MarkdownUI

enum NewUIPreviewRecordDetailSection: String, CaseIterable, Identifiable {
    case organized
    case raw
    case todos

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .organized: return "整理内容"
        case .raw: return "原文"
        case .todos: return "待办"
        }
    }
}

/// Pure projection used by the preview UI and tests. Keeping redaction here means
/// encrypted fixture content never reaches search, sharing, or a child content view.
struct NewUIPreviewRecordPresentation {
    static func organizedMarkdown(for record: NoteRecord) -> String {
        guard !record.isEncrypted else { return "" }

        let summary = trimmed(record.summary)
        let detail = trimmed(record.detailedContent)
        var sections: [String] = []

        if !summary.isEmpty, summary != detail {
            sections.append("## \(String(localized: "摘要"))\n\n\(summary)")
        }
        if !detail.isEmpty {
            sections.append("## \(String(localized: "详细内容"))\n\n\(detail)")
        }
        if !record.keyPoints.isEmpty {
            let points = record.keyPoints
                .map(trimmed)
                .filter { !$0.isEmpty }
                .map { "- \($0)" }
                .joined(separator: "\n")
            if !points.isEmpty {
                sections.append("## \(String(localized: "要点"))\n\n\(points)")
            }
        }
        if !record.definitions.isEmpty {
            let definitions = record.definitions.compactMap { definition -> String? in
                let term = trimmed(definition.term)
                let explanation = trimmed(definition.explanation)
                guard !term.isEmpty || !explanation.isEmpty else { return nil }
                return "- " + definitionLine(term: "**\(term)**", explanation: explanation)
            }.joined(separator: "\n")
            if !definitions.isEmpty {
                sections.append("## \(String(localized: "术语"))\n\n\(definitions)")
            }
        }

        return sections.joined(separator: "\n\n")
    }

    static func visibleText(
        for section: NewUIPreviewRecordDetailSection,
        record: NoteRecord,
        todos: [String]
    ) -> String {
        guard !record.isEncrypted else { return "" }

        switch section {
        case .organized:
            return organizedPlainText(for: record)
        case .raw:
            return trimmed(record.ocrText)
        case .todos:
            return todos.map(trimmed).filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    static func matches(
        query: String,
        section: NewUIPreviewRecordDetailSection,
        record: NoteRecord,
        todos: [String]
    ) -> Bool {
        let query = trimmed(query)
        guard !query.isEmpty, !record.isEncrypted else { return false }
        return visibleText(for: section, record: record, todos: todos)
            .localizedCaseInsensitiveContains(query)
    }

    static func shareText(for record: NoteRecord, todos: [String]) -> String {
        guard !record.isEncrypted else { return "" }
        return [
            trimmed(record.title),
            visibleText(for: .organized, record: record, todos: todos)
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func organizedPlainText(for record: NoteRecord) -> String {
        let summary = trimmed(record.summary)
        let detail = trimmed(record.detailedContent)
        var sections: [String] = []

        if !summary.isEmpty, summary != detail {
            sections.append("\(String(localized: "摘要"))\n\(summary)")
        }
        if !detail.isEmpty {
            sections.append("\(String(localized: "详细内容"))\n\(detail)")
        }
        let points = record.keyPoints.map(trimmed).filter { !$0.isEmpty }
        if !points.isEmpty {
            sections.append("\(String(localized: "要点"))\n" + points.map { "• \($0)" }.joined(separator: "\n"))
        }
        let definitions = record.definitions.compactMap { definition -> String? in
            let term = trimmed(definition.term)
            let explanation = trimmed(definition.explanation)
            guard !term.isEmpty || !explanation.isEmpty else { return nil }
            return definitionLine(term: term, explanation: explanation)
        }
        if !definitions.isEmpty {
            sections.append("\(String(localized: "术语"))\n" + definitions.joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n")
    }

    private static func definitionLine(term: String, explanation: String) -> String {
        String(
            format: String(localized: "%1$@：%2$@"),
            locale: Locale.current,
            term,
            explanation
        )
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NewUIPreviewRecordDetailView: View {
    let fixture: NewUIPreviewRecordFixture
    var transitionOrigin: NewUIPreviewRecordOrigin? = nil
    var transitionNamespace: Namespace.ID? = nil
    let onClose: () -> Void

    @State private var selectedSection: NewUIPreviewRecordDetailSection = .organized
    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var selectedImageIndex = 0
    @State private var showsFullScreenMedia = false
    @State private var showsAppendSheet = false
    @State private var showsEmergenceSheet = false
    @State private var showsInfoSheet = false
    @State private var showsScrollToTop = false

    private let topAnchor = "new-ui-preview-detail-top"

    var body: some View {
        ZStack {
            NewUIPreviewRecordDetailBackground(
                recordID: fixture.id,
                origin: transitionOrigin,
                namespace: transitionNamespace
            )

            VStack(spacing: 0) {
                toolbar

                ScrollViewReader { proxy in
                    ZStack(alignment: .bottomTrailing) {
                        detailScroll

                        if showsScrollToTop {
                            Button {
                                withAnimation(.easeOut(duration: 0.28)) {
                                    proxy.scrollTo(topAnchor, anchor: .top)
                                }
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(Color.newUIPreviewPrimary)
                                    .frame(width: 48, height: 48)
                                    .contentShape(Circle())
                                    .newUIPreviewGlass(in: Circle(), interactive: true)
                            }
                            .buttonStyle(NewUIPreviewPressStyle())
                            .accessibilityLabel("返回顶部")
                            .padding(.trailing, 20)
                            .padding(.bottom, 16)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionDock
        }
        .sheet(isPresented: $showsAppendSheet) {
            NewUIPreviewAppendRecordSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsEmergenceSheet) {
            NewUIPreviewEmergenceSheet(recordTitle: safeTitle)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsInfoSheet) {
            infoSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showsFullScreenMedia) {
            NewUIPreviewFullScreenMediaView(
                media: fixture.record.isEncrypted ? [] : fixture.media,
                initialIndex: selectedImageIndex
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            NewUIPreviewCircleButton(symbol: "chevron.left", label: "返回", action: onClose)

            Spacer(minLength: 4)

            if isSearching {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.newUIPreviewSecondary)
                    TextField("在当前内容中搜索", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(fixture.record.isEncrypted)
                    Button {
                        searchQuery = ""
                        isSearching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.newUIPreviewSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel("关闭搜索")
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .frame(height: 50)
                .newUIPreviewGlass(in: Capsule(), interactive: true)
            } else {
                NewUIPreviewCircleButton(
                    symbol: "magnifyingglass",
                    label: "搜索当前记录",
                    action: { isSearching = true }
                )
                .disabled(fixture.record.isEncrypted)

                if fixture.record.isEncrypted {
                    NewUIPreviewCircleButton(symbol: "square.and.arrow.up", label: "分享", action: {})
                        .disabled(true)
                } else {
                    ShareLink(item: NewUIPreviewRecordPresentation.shareText(
                        for: fixture.record,
                        todos: fixture.todos
                    )) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.newUIPreviewPrimary.opacity(0.9))
                            .frame(width: 50, height: 50)
                            .contentShape(Circle())
                            .newUIPreviewGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(NewUIPreviewPressStyle())
                    .accessibilityLabel("分享")
                }

                Menu {
                    if fixture.record.isEncrypted {
                        Button("已加密（预览）", systemImage: "lock.fill") {}
                            .disabled(true)
                    } else {
                        Button("编辑", systemImage: "pencil") {}
                        Button("更多信息", systemImage: "info.circle") { showsInfoSheet = true }
                        Button("加密", systemImage: "lock") {}
                        Divider()
                        Button("删除", systemImage: "trash", role: .destructive) {}
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.newUIPreviewPrimary.opacity(0.9))
                        .frame(width: 50, height: 50)
                        .contentShape(Circle())
                        .newUIPreviewGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(NewUIPreviewPressStyle())
                .accessibilityLabel("更多")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.newUIPreviewBackground.opacity(0.92))
        .zIndex(2)
    }

    private var detailScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Color.clear
                    .frame(height: 1)
                    .id(topAnchor)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: NewUIPreviewDetailScrollOffsetKey.self,
                                value: proxy.frame(in: .named("new-ui-preview-detail-scroll")).minY
                            )
                        }
                    }

                if fixture.record.isEncrypted {
                    encryptedPlaceholder
                        .padding(.top, 84)
                        .padding(.bottom, 36)
                } else {
                    mediaHeader
                    recordHeader
                }

                Section {
                    detailDocument
                        .padding(.horizontal, 22)
                        .padding(.top, 24)
                        .padding(.bottom, 132)
                } header: {
                    sectionSelector
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.newUIPreviewBackground.opacity(0.94))
                }
            }
        }
        .coordinateSpace(name: "new-ui-preview-detail-scroll")
        .onPreferenceChange(NewUIPreviewDetailScrollOffsetKey.self) { offset in
            let shouldShow = offset < -480
            guard showsScrollToTop != shouldShow else { return }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.18)) {
                    showsScrollToTop = shouldShow
                }
            }
        }
    }

    @ViewBuilder
    private var mediaHeader: some View {
        if fixture.media.count == 1, let media = fixture.media.first {
            Button {
                selectedImageIndex = 0
                showsFullScreenMedia = true
            } label: {
                Image(media.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看图片")
            .padding(.horizontal, 20)
            .padding(.top, 8)
        } else if fixture.media.count > 1 {
            VStack(spacing: 10) {
                TabView(selection: $selectedImageIndex) {
                    ForEach(Array(fixture.media.enumerated()), id: \.offset) { index, media in
                        Button {
                            selectedImageIndex = index
                            showsFullScreenMedia = true
                        } label: {
                            Image(media.imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 350)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                        .accessibilityLabel("第 \(index + 1) 张，共 \(fixture.media.count) 张")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 360)

                Text("第 \(selectedImageIndex + 1) 张，共 \(fixture.media.count) 张")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.newUIPreviewSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.top, 8)
        }
    }

    private var recordHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(fixture.record.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.newUIPreviewPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Label(
                    fixture.record.capturedAt.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "clock"
                )
                Text(statusLabel)
            }
            .font(.subheadline)
            .foregroundStyle(Color.newUIPreviewSecondary)

            metadata
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 22)
    }

    private var metadata: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                metadataChip(sourceLabel, symbol: sourceSymbol)
                if let eventName = fixture.eventName, !eventName.isEmpty {
                    metadataChip(eventName, symbol: "calendar")
                }
                if let folderName = fixture.folderName, !folderName.isEmpty {
                    metadataChip(folderName, symbol: "folder")
                }
                metadataChip(statusLabel, symbol: statusSymbol)
            }
        }
    }

    private func metadataChip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.newUIPreviewSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
    }

    private var sectionSelector: some View {
        HStack(spacing: 4) {
            ForEach(NewUIPreviewRecordDetailSection.allCases) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedSection = section
                    }
                } label: {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            selectedSection == section
                                ? Color.newUIPreviewAccent
                                : Color.newUIPreviewSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(NewUIPreviewPressStyle())
                .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
            }
        }
        .padding(4)
        .newUIPreviewGlass(in: RoundedRectangle(cornerRadius: 8, style: .continuous), interactive: true)
    }

    @ViewBuilder
    private var detailDocument: some View {
        if fixture.record.isEncrypted {
            emptyState("加密记录的内容不可在预览中搜索或显示。", symbol: "lock.fill")
        } else {
            let visibleText = NewUIPreviewRecordPresentation.visibleText(
                for: selectedSection,
                record: fixture.record,
                todos: fixture.todos
            )

            if visibleText.isEmpty {
                switch selectedSection {
                case .organized:
                    emptyState("这条记录暂无整理内容。", symbol: "doc.text")
                case .raw:
                    emptyState("这条记录没有独立原文。", symbol: "text.viewfinder")
                case .todos:
                    emptyState("这条记录没有待办。", symbol: "checklist")
                }
            } else if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                highlightedText(visibleText, query: searchQuery)
                    .font(.body)
                    .lineSpacing(6)
                    .textSelection(.enabled)
            } else {
                switch selectedSection {
                case .organized:
                    Markdown(NewUIPreviewRecordPresentation.organizedMarkdown(for: fixture.record))
                        .textSelection(.enabled)
                case .raw:
                    Text(visibleText)
                        .font(.body)
                        .lineSpacing(6)
                        .textSelection(.enabled)
                case .todos:
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(fixture.todos.enumerated()), id: \.offset) { _, todo in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.newUIPreviewAccent)
                                Text(todo)
                                    .font(.body)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }

            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !NewUIPreviewRecordPresentation.matches(
                    query: searchQuery,
                    section: selectedSection,
                    record: fixture.record,
                    todos: fixture.todos
               ) {
                Text("当前内容中没有匹配结果")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.newUIPreviewSecondary)
                    .padding(.top, 16)
            }
        }
    }

    private var encryptedPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.doc.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.newUIPreviewAccent)
                .frame(width: 72, height: 72)
                .background(Color.newUIPreviewAccent.opacity(0.12), in: Circle())
            Text("此记录已加密")
                .font(.title3.weight(.semibold))
            Text("预览不会读取或显示这条记录的标题、正文、图片与待办。")
                .font(.subheadline)
                .foregroundStyle(Color.newUIPreviewSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 36)
    }

    private func emptyState(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(Color.newUIPreviewSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 24)
    }

    private func highlightedText(_ text: String, query: String) -> Text {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return Text(text) }

        var result = Text("")
        var remaining = text.startIndex..<text.endIndex
        while let match = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: remaining) {
            result = result + Text(String(text[remaining.lowerBound..<match.lowerBound]))
            result = result + Text(String(text[match])).bold().foregroundColor(Color.newUIPreviewAccent)
            remaining = match.upperBound..<text.endIndex
        }
        return result + Text(String(text[remaining]))
    }

    private var actionDock: some View {
        HStack(spacing: 10) {
            actionButton("追加记录", symbol: "plus") { showsAppendSheet = true }
            actionButton("涌现", symbol: "sparkles") { showsEmergenceSheet = true }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.newUIPreviewBackground.opacity(0.9))
    }

    private func actionButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(Color.newUIPreviewPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .newUIPreviewGlass(
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                    interactive: true
                )
        }
        .buttonStyle(NewUIPreviewPressStyle())
    }

    private var infoSheet: some View {
        NavigationStack {
            List {
                LabeledContent("来源", value: sourceLabel)
                LabeledContent(
                    "创建时间",
                    value: fixture.record.capturedAt.formatted(date: .abbreviated, time: .standard)
                )
                if let eventName = fixture.eventName {
                    LabeledContent("日程", value: eventName)
                }
                if let folderName = fixture.folderName {
                    LabeledContent("文件夹", value: folderName)
                }
            }
            .navigationTitle("更多信息")
        }
    }

    private var safeTitle: String {
        fixture.record.isEncrypted ? String(localized: "加密记录") : fixture.record.title
    }

    private var sourceLabel: String {
        fixture.previewSource.title
    }

    private var sourceSymbol: String {
        fixture.previewSource.symbolName
    }

    private var statusLabel: String {
        switch fixture.record.processingState {
        case .pending: return String(localized: "等待处理")
        case .processing: return String(localized: "正在处理")
        case .completed: return String(localized: "已整理")
        case .failed: return String(localized: "处理失败")
        case .deadLetter: return String(localized: "重试已停止")
        }
    }

    private var statusSymbol: String {
        switch fixture.record.processingState {
        case .pending: return "clock"
        case .processing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle"
        case .failed, .deadLetter: return "exclamationmark.triangle"
        }
    }
}

struct NewUIPreviewRecordDetailBackground: View {
    let recordID: UUID
    let origin: NewUIPreviewRecordOrigin?
    let namespace: Namespace.ID?

    var body: some View {
        ZStack {
            Color.newUIPreviewBackground

            Rectangle()
                .fill(Color.newUIPreviewBackground)
                .newUIPreviewRecordTransitionSurface(
                    recordID: recordID,
                    origin: origin,
                    namespace: namespace,
                    isSource: false
                )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NewUIPreviewDetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct NewUIPreviewFullScreenMediaView: View {
    let media: [NewUIPreviewMedia]
    let initialIndex: Int

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int

    init(media: [NewUIPreviewMedia], initialIndex: Int) {
        self.media = media
        self.initialIndex = initialIndex
        _selectedIndex = State(initialValue: min(max(initialIndex, 0), max(media.count - 1, 0)))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedIndex) {
                ForEach(Array(media.enumerated()), id: \.offset) { index, item in
                    Image(item.imageName)
                        .resizable()
                        .scaledToFit()
                        .tag(index)
                        .accessibilityLabel("第 \(index + 1) 张，共 \(media.count) 张")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.5), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("关闭图片")
            .padding(18)
        }
    }
}

private struct NewUIPreviewAppendRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextEditor(text: $text)
                    .font(.body)
                    .padding(10)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("补充这条记录…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
            }
            .padding(20)
            .navigationTitle("追加记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct NewUIPreviewEmergenceSheet: View {
    let recordTitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("涌现", systemImage: "sparkles")
                .font(.title2.bold())
                .foregroundStyle(Color.newUIPreviewPrimary)
            Text(recordTitle)
                .font(.headline)
                .foregroundStyle(Color.newUIPreviewSecondary)
            Divider()
            Text("这里将呈现由当前记录延伸出的联系、问题与新想法。")
                .font(.body)
                .foregroundStyle(Color.newUIPreviewPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}
