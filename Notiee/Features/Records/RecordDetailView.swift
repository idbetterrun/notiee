import SwiftUI
import MarkdownUI

struct RecordDetailView: View {
    @ObservedObject private var viewModel: RecordDetailViewModel
    @State private var loadedImages: [UIImage] = []
    @State private var currentImageIndex = 0
    
    @State private var showEditSheet = false
    @State private var showInfoSheet = false
    @State private var isOCRExpanded = false
    
    @State private var isSummaryExpanded = true
    @State private var isDetailExpanded = true
    @State private var isTodosExpanded = true
    
    @State private var fullScreenItem: FullScreenImageItem?
    @State private var unlockedRecord: NoteRecord?
    @State private var unlockedTodos: [NoteTodo] = []
    @State private var unlockFailed = false
    @StateObject private var appLock = AppLockManager.shared
    
    @AppStorage(UDK.labMarkdownRenderingEnabled) private var markdownRenderingEnabled = false
    
    @Environment(\.dismiss) private var dismiss

    init(viewModel: RecordDetailViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Group {
            if viewModel.record.isEncrypted && unlockedRecord == nil {
                lockedPlaceholder
            } else {
                contentScrollView
            }
        }
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("导出为 .tmn 文件") {
                        Task {
                            do {
                                let url = try await TMNExportService.export(record: viewModel.record, store: viewModel.store)
                                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let window = windowScene.windows.first,
                                   let rootVC = window.rootViewController {
                                    rootVC.present(activityVC, animated: true)
                                }
                            } catch {
                                print("Export failed: \(error.localizedDescription)")
                            }
                        }
                    }
                    ShareLink(
                        item: buildShareContent(),
                        subject: Text(viewModel.record.title),
                        message: Text("分享一条 Notiee 记录")
                    ) {
                        Label("分享...", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.record.isEncrypted)

                Menu {
                    Button("编辑", systemImage: "pencil") { showEditSheet = true }
                    Button("更多信息", systemImage: "info.circle") { showInfoSheet = true }
                    if viewModel.record.isEncrypted {
                        Button("已加密（在设置中管理）", systemImage: "lock.fill") {}
                            .disabled(true)
                    } else {
                        Button("加密该条拍记", systemImage: "lock") {
                            viewModel.store.encryptRecord(id: viewModel.record.id)
                            dismiss()
                        }
                    }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) {
                        viewModel.deleteRecord()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            RecordEditSheet(record: viewModel.record, todos: viewModel.todos) { updatedRecord, updatedTodos in
                viewModel.saveEdits(updatedRecord: updatedRecord, updatedTodos: updatedTodos)
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            infoSheetContent
                .presentationDetents([.medium])
        }
        .fullScreenCover(item: $fullScreenItem) { item in
            FullScreenImageView(images: item.images, initialIndex: item.initialIndex)
        }
        .task(id: viewModel.record.id) {
            await viewModel.loadRelatedRecords()
        }
        .onAppear {
            Task.detached(priority: .userInitiated) {
                var images: [UIImage] = []
                for path in viewModel.record.localImagePaths {
                    if path.hasSuffix(".enc") {
                        let img = await MainActor.run {
                            SecureRecordCodec(crypto: CryptoService.shared()).decryptedImage(atEncryptedPath: path)
                        }
                        if let img = img { images.append(img) }
                    } else if let data = LocalImageStore.readImageData(path: path),
                              let img = UIImage(data: data) {
                        images.append(img)
                    }
                }
                let finalImages = images
                await MainActor.run { self.loadedImages = finalImages }
            }
        }
    }

    private var contentScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if viewModel.record.source == .photo {
                    imagePreview
                }
                keyPointsSection
                definitionsSection
                summarySection
                detailedContentSection
                todoSection
                continuationSection
                relatedNotesSection
                ocrSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .scrollContentTouchFix()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var lockedPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundColor(.accentColor)
            Text("此拍记已加密").font(.headline)
            Button {
                Task {
                    if await appLock.authenticateWithBiometrics(reason: "查看加密拍记") || !appLock.biometricEnabled {
                        if let result = viewModel.store.decryptedForViewing(viewModel.record) {
                            unlockedRecord = result.record
                            unlockedTodos = result.todos
                        } else {
                            unlockFailed = true
                        }
                    }
                }
            } label: {
                Label("解锁查看", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            if unlockFailed { Text("解锁失败").foregroundColor(.red) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private var displayRecord: NoteRecord { unlockedRecord ?? viewModel.record }
    private var displaySummaryText: String {
        let r = displayRecord
        guard !r.summary.isEmpty else { return viewModel.summaryText }
        return r.summary
    }
    private var displayOcrText: String {
        let r = displayRecord
        guard !r.ocrText.isEmpty else { return viewModel.ocrText }
        return r.ocrText
    }
    private var displayTodos: [NoteTodo] {
        unlockedRecord != nil ? unlockedTodos : viewModel.todos
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Menu {
                    ForEach(viewModel.availableEvents) { event in
                        Button(event.title) {
                            viewModel.reassignEvent(to: event.id)
                        }
                    }
                    
                    Divider()
                    
                    Button("未分类") {
                        viewModel.reassignEvent(to: nil)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Label(viewModel.eventTitle, systemImage: viewModel.eventTitle == "未分类" ? "tray" : "calendar")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.12), in: Capsule())
                }
                
                Menu {
                    ForEach(viewModel.availableFolders) { folder in
                        Button(folder.name) {
                            viewModel.reassignFolder(to: folder.id)
                        }
                    }
                    Divider()
                    Button("移出文件夹") {
                        viewModel.reassignFolder(to: nil)
                    }
                } label: {
                    HStack(spacing: 6) {
                        let folderName = viewModel.availableFolders.first(where: { $0.id == viewModel.record.folderID })?.name ?? "未加入文件夹"
                        Label(folderName, systemImage: "folder")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.secondary.opacity(0.12), in: Capsule())
                }
            }

            Text(displayRecord.title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            HStack(spacing: 10) {
                Label(viewModel.statusTitle, systemImage: viewModel.record.processingState.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(viewModel.record.processingState.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(viewModel.record.processingState.tint.opacity(0.12), in: Capsule())

                Text(viewModel.store.formattedDateWithWeek(for: viewModel.record.capturedAt) + " " + viewModel.record.capturedAt.formatted(.dateTime.hour().minute()))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    
                Spacer()
                
                if viewModel.record.processingState == .pending {
                    Button("触发 AI 分析") {
                        viewModel.processRecord()
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                } else if viewModel.record.processingState == .failed {
                    Button("重试") {
                        viewModel.retryProcessing()
                    }
                    .font(.caption.weight(.bold))
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
    }

    private var imagePreview: some View {
        Group {
            if !loadedImages.isEmpty {
                TabView(selection: $currentImageIndex) {
                    ForEach(0..<loadedImages.count, id: \.self) { index in
                        Image(uiImage: loadedImages[index])
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 300)
                            .clipped()
                            .onTapGesture {
                                fullScreenItem = FullScreenImageItem(images: loadedImages, initialIndex: index)
                            }
                            .contextMenu {
                                ShareLink(item: Image(uiImage: loadedImages[index]), preview: SharePreview("图片", image: Image(uiImage: loadedImages[index]))) {
                                    Label("分享", systemImage: "square.and.arrow.up")
                                }
                            }
                            .tag(index)
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.8), lineWidth: 1)
                }
            } else {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.linearGradient(
                        colors: [
                            viewModel.record.processingState.tint.opacity(0.18),
                            Color(.secondarySystemGroupedBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.28, contentMode: .fit)
                    .overlay(alignment: .center) {
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 44, weight: .regular))
                                .foregroundStyle(viewModel.record.processingState.tint)
        
                            Text("无预览图片")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(.white.opacity(0.8), lineWidth: 1)
                    }
            }
        }
    }

    private var keyPointsSection: some View {
        let points = displayRecord.keyPoints
        guard !points.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            DetailSection(title: "📌 知识点", systemImage: "lightbulb.fill", isExpanded: .constant(true)) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(points.indices, id: \.self) { idx in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1).")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(NotieeColors.themed(.orange))
                                .frame(width: 24, alignment: .leading)
                            Text(points[idx])
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    private var definitionsSection: some View {
        let defs = displayRecord.definitions
        guard !defs.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            DetailSection(title: "📖 名词解释", systemImage: "book.pages.fill", isExpanded: .constant(true)) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(defs.indices, id: \.self) { idx in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(defs[idx].term)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(defs[idx].explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if idx < defs.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    private var summarySection: some View {
        guard viewModel.showsSummarySection else { return AnyView(EmptyView()) }
        return AnyView(
            DetailSection(title: "AI 摘要", systemImage: "sparkles", isExpanded: $isSummaryExpanded) {
                Text(displaySummaryText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }
    
    private var detailedContentSection: some View {
            let content = displayRecord.detailedContent
            let hasMarkdown = content.contains("#") || content.contains("*") || content.contains("- ") || content.contains("`") || content.contains(">") || content.contains("[")
            let shouldRenderMarkdown = markdownRenderingEnabled && hasMarkdown

            return DetailSection(title: "详细内容", systemImage: "doc.text.magnifyingglass", isExpanded: $isDetailExpanded, showMarkdownIcon: shouldRenderMarkdown) {
                Group {
                    if content.isEmpty {
                        Text("无详细内容")
                            .foregroundStyle(.primary)
                    } else if shouldRenderMarkdown {
                        Markdown(content)
                            .textSelection(.enabled)
                    } else {
                        Text(content)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var todoSection: some View {
        // 待办为空时：拍照记录展示「将自动提取」占位；纯文本/Spark 直接隐藏。
        guard !displayTodos.isEmpty || viewModel.showsTodoPlaceholder else {
            return AnyView(EmptyView())
        }
        return AnyView(
            DetailSection(title: "待办事项", systemImage: "checklist", isExpanded: $isTodosExpanded) {
                if displayTodos.isEmpty {
                    Text("AI 提取出的行动项会显示在这里。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 12) {
                        ForEach(displayTodos) { todo in
                            SwipeableTodoRow(
                                todo: todo,
                                onToggleComplete: { viewModel.toggleTodo(id: todo.id) },
                                onDelete: { viewModel.deleteTodo(id: todo.id) }
                            )
                        }

                        if viewModel.showsTodoPlaceholder, !viewModel.record.localImagePaths.isEmpty {
                            Divider()

                            VStack(alignment: .leading, spacing: 4) {
                                Text("本地路径")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                ForEach(viewModel.record.localImagePaths, id: \.self) { path in
                                    Text(path)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        )
    }

    private var continuationSection: some View {
        guard let previousRecord = viewModel.continuationRecord else { return AnyView(EmptyView()) }
        return AnyView(
            NavigationLink {
                RecordDetailView(viewModel: RecordDetailViewModel(record: previousRecord, store: viewModel.store))
            } label: {
                HStack {
                    Image(systemName: "link")
                        .foregroundColor(NotieeColors.themed(.blue))
                    Text("可能为上次笔记的续篇 → 查看上篇")
                        .font(.subheadline)
                        .foregroundColor(NotieeColors.themed(.blue))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.06))
                .cornerRadius(10)
            }
            .padding(.horizontal)
        )
    }

    private var relatedNotesSection: some View {
        let related = viewModel.relatedRecords
        guard !related.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            DetailSection(title: "🔗 相关内容", systemImage: "rectangle.3.group.fill", isExpanded: .constant(true)) {
                VStack(spacing: 8) {
                    ForEach(related) { note in
                        NavigationLink {
                            RecordDetailView(viewModel: RecordDetailViewModel(record: note, store: viewModel.store))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(note.capturedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        )
    }

    private var ocrSection: some View {
        guard viewModel.showsOCRSection else { return AnyView(EmptyView()) }
        return AnyView(
            DetailSection(title: "OCR 原文", systemImage: "text.viewfinder", isExpanded: $isOCRExpanded) {
                Text(displayOcrText)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }
    
    private var infoSheetContent: some View {
        NavigationStack {
            List {
                Section("基础信息") {
                    LabeledContent("Token 消耗", value: "\(viewModel.record.tokenUsage) tk")
                    if let deviceName = viewModel.record.deviceName {
                        LabeledContent("设备名称", value: deviceName)
                    }
                    LabeledContent("创建时间", value: viewModel.record.capturedAt.formatted(date: .abbreviated, time: .standard))
                    if let editDate = viewModel.record.editedAt {
                        LabeledContent("最近编辑", value: editDate.formatted(date: .abbreviated, time: .standard))
                    } else {
                        LabeledContent("编辑状态", value: "未编辑")
                    }
                }
                
                Section("AI 模型信息") {
                    if let models = viewModel.record.modelsUsed, models.count >= 2 {
                        LabeledContent("视觉模型", value: models[0])
                        LabeledContent("文本模型", value: models[1])
                    } else {
                        Text("暂无模型信息")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("记录信息")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func buildShareContent() -> String {
        var content = "【\(viewModel.record.title)】\n\n"
        content += "📝 摘要:\n\(viewModel.summaryText)\n\n"
        if !viewModel.record.detailedContent.isEmpty {
            content += "📄 详细内容:\n\(viewModel.record.detailedContent)\n\n"
        }
        if !viewModel.todos.isEmpty {
            content += "✅ 待办:\n"
            for todo in viewModel.todos {
                content += "- [\(todo.isCompleted ? "x" : " ")] \(todo.content)\n"
            }
            content += "\n"
        }
        content += "🔍 OCR:\n\(viewModel.ocrText)"
        return content
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    var showMarkdownIcon: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if showMarkdownIcon {
                        Image(systemName: "m.square")
                            .foregroundStyle(.blue)
                            .font(.subheadline)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
    }
}

struct FullScreenImageItem: Identifiable {
    let id = UUID()
    let images: [UIImage]
    let initialIndex: Int
}

struct FullScreenImageView: View {
    let images: [UIImage]
    let initialIndex: Int
    @Environment(\.dismiss) var dismiss
    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0
    @State private var currentIndex: Int
    @State private var showSaveSuccess = false
    
    init(images: [UIImage], initialIndex: Int) {
        self.images = images
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $currentIndex) {
                ForEach(0..<images.count, id: \.self) { index in
                    Image(uiImage: images[index])
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(currentIndex == index ? finalScale * currentScale : 1.0)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    if currentIndex == index {
                                        currentScale = value
                                    }
                                }
                                .onEnded { value in
                                    if currentIndex == index {
                                        finalScale = max(1.0, min(finalScale * value, 5.0))
                                        currentScale = 1.0
                                    }
                                }
                        )
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
            .ignoresSafeArea()
            
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                
                Spacer()
                
                HStack {
                    Spacer()
                    Button {
                        saveCurrentImage()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .overlay {
            if showSaveSuccess {
                VStack {
                    Image(systemName: "checkmark")
                        .font(.largeTitle)
                        .padding()
                    Text("已保存到相册")
                        .font(.headline)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
            }
        }
    }
    
    private func saveCurrentImage() {
        let saver = ImageSaver()
        saver.onSuccess = {
            withAnimation {
                showSaveSuccess = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSaveSuccess = false
                }
            }
        }
        saver.writeToPhotoAlbum(image: images[currentIndex])
    }
}



#Preview {
    let store = NotieeStore.sample()
    return NavigationStack {
        RecordDetailView(viewModel: RecordDetailViewModel(record: store.sortedRecords[0], store: store))
    }
}


// MARK: - ScrollView Touch Fix

private extension View {
    func scrollContentTouchFix() -> some View {
        background(ScrollTouchFixer())
    }
}

private struct ScrollTouchFixer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isHidden = true
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            var parent = uiView.superview
            while parent != nil {
                if let scrollView = parent as? UIScrollView {
                    scrollView.delaysContentTouches = false
                    break
                }
                parent = parent?.superview
            }
        }
    }
}

struct RecordEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NoteRecord
    @State private var draftTodos: [NoteTodo]
    let onSave: (NoteRecord, [NoteTodo]) -> Void
    
    init(record: NoteRecord, todos: [NoteTodo], onSave: @escaping (NoteRecord, [NoteTodo]) -> Void) {
        self._draft = State(initialValue: record)
        self._draftTodos = State(initialValue: todos)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("记录标题", text: $draft.title)
                }
                
                Section("AI 摘要") {
                    TextEditor(text: $draft.summary)
                        .frame(minHeight: 80)
                }
                
                Section("详细内容") {
                    TextEditor(text: $draft.detailedContent)
                        .frame(minHeight: 120)
                }
                
                Section("待办事项") {
                    ForEach($draftTodos) { $todo in
                        TextField("待办内容", text: $todo.content)
                    }
                    .onDelete { indices in
                        draftTodos.remove(atOffsets: indices)
                    }
                    Button("添加待办") {
                        draftTodos.append(NoteTodo(recordID: draft.id, content: ""))
                    }
                }
                
                Section("OCR 原文") {
                    TextEditor(text: $draft.ocrText)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.editedAt = Date()
                        onSave(draft, draftTodos)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SwipeableTodoRow: View {
    let todo: NoteTodo
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isSwiping = false
    
    var body: some View {
        ZStack {
            // Background for swipe actions
            HStack {
                // Left-to-right background (Complete/Uncomplete)
                if offset > 0 {
                    Rectangle()
                        .fill(todo.isCompleted ? .orange : .green)
                        .overlay(alignment: .leading) {
                            Image(systemName: todo.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                .foregroundStyle(.white)
                                .font(.title3.weight(.semibold))
                                .padding(.leading, 20)
                        }
                }
                
                Spacer()
                
                // Right-to-left background (Delete)
                if offset < 0 {
                    Rectangle()
                        .fill(.red)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "trash")
                                .foregroundStyle(.white)
                                .font(.title3.weight(.semibold))
                                .padding(.trailing, 20)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Foreground row
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onToggleComplete()
                    }
                } label: {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.isCompleted ? .green : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Text(todo.content)
                    .font(.body.weight(.medium))
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .strikethrough(todo.isCompleted)

                Spacer()
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isSwiping = true
                        let width = value.translation.width
                        // Add some resistance
                        offset = width > 0 ? pow(width, 0.8) : -pow(-width, 0.8)
                    }
                    .onEnded { value in
                        isSwiping = false
                        let width = value.translation.width
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if width > 80 {
                                // Trigger Complete
                                onToggleComplete()
                                offset = 0
                            } else if width < -80 {
                                // Trigger Delete
                                onDelete()
                                offset = 0
                            } else {
                                offset = 0
                            }
                        }
                    }
            )
        }
    }
}
