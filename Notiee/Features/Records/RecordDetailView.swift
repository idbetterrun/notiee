import SwiftUI

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
    
    @Environment(\.dismiss) private var dismiss

    init(viewModel: RecordDetailViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                imagePreview
                summarySection
                detailedContentSection
                todoSection
                ocrSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("编辑", systemImage: "pencil") {
                    showEditSheet = true
                }
                Button("信息", systemImage: "info.circle") {
                    showInfoSheet = true
                }
                
                ShareLink(
                    item: buildShareContent(),
                    subject: Text(viewModel.record.title),
                    message: Text("分享一条 Notiee 记录")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Button("删除", systemImage: "trash", role: .destructive) {
                    viewModel.deleteRecord()
                    dismiss()
                }
                .tint(.red)
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
            FullScreenImageView(image: item.image)
        }
        .onAppear {
            Task.detached(priority: .userInitiated) {
                var images: [UIImage] = []
                for path in viewModel.record.localImagePaths {
                    if let img = await MainActor.run(body: { LocalImageStore.shared.loadImage(path: path) }) {
                        images.append(img)
                    }
                }
                let finalImages = images
                await MainActor.run { self.loadedImages = finalImages }
            }
        }
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

            Text(viewModel.record.title)
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

                Text(viewModel.record.capturedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
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
                                fullScreenItem = FullScreenImageItem(image: loadedImages[index])
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

    private var summarySection: some View {
        DetailSection(title: "AI 摘要", systemImage: "sparkles", isExpanded: $isSummaryExpanded) {
            Text(viewModel.summaryText)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var detailedContentSection: some View {
        DetailSection(title: "详细内容", systemImage: "doc.text.magnifyingglass", isExpanded: $isDetailExpanded) {
            Text(viewModel.record.detailedContent.isEmpty ? "无详细内容" : viewModel.record.detailedContent)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var todoSection: some View {
        DetailSection(title: "待办事项", systemImage: "checklist", isExpanded: $isTodosExpanded) {
            if viewModel.todos.isEmpty {
                Text("AI 提取出的行动项会显示在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.todos) { todo in
                        SwipeableTodoRow(
                            todo: todo,
                            onToggleComplete: { viewModel.toggleTodo(id: todo.id) },
                            onDelete: { viewModel.deleteTodo(id: todo.id) }
                        )
                    }
                    
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

    private var ocrSection: some View {
        DetailSection(title: "OCR 原文", systemImage: "text.viewfinder", isExpanded: .constant(true)) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation { isOCRExpanded.toggle() }
                } label: {
                    HStack {
                        Text(isOCRExpanded ? "收起" : "展开")
                            .font(.caption.weight(.semibold))
                        Image(systemName: isOCRExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.blue)
                }
                
                if isOCRExpanded {
                    Text(viewModel.ocrText)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
    
    private var infoSheetContent: some View {
        NavigationStack {
            List {
                Section("基础信息") {
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
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $isExpanded) {
                content
                    .padding(18)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            } label: {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .tint(.secondary)
        }
    }
}

struct FullScreenImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct FullScreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) var dismiss
    @State private var currentScale: CGFloat = 1.0
    @State private var finalScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(finalScale * currentScale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            currentScale = value
                        }
                        .onEnded { value in
                            finalScale = max(1.0, min(finalScale * value, 5.0))
                            currentScale = 1.0
                        }
                )
            
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
                    
                    ShareLink(item: Image(uiImage: image), preview: SharePreview("图片", image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                
                Spacer()
            }
        }
    }
}



#Preview {
    let store = NotieeStore.sample()
    return NavigationStack {
        RecordDetailView(viewModel: RecordDetailViewModel(record: store.sortedRecords[0], store: store))
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
