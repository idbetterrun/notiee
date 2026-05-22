import SwiftUI

struct RecordsView: View {
    @ObservedObject private var store: NotieeStore
    @State private var searchText = ""
    
    @State private var showingCreateFolderAlert = false
    @State private var newFolderName = ""
    
    @State private var showingRenameFolderAlert = false
    @State private var folderToRename: CustomFolder?
    @State private var renameFolderName = ""
    
    @State private var showingDeleteFolderAlert = false
    @State private var folderToDelete: CustomFolder?

    @MainActor
    init() {
        self.store = NotieeStore.sample()
    }

    init(store: NotieeStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            List {
                Section("系统文件夹") {
                    NavigationLink(destination: GenericRecordListView(title: "收藏夹", systemImage: "star.fill", records: store.favoriteRecords, store: store)) {
                        FolderSummaryRow(title: "收藏夹", systemImage: "star.fill", count: store.favoriteRecords.count)
                    }
                    NavigationLink(destination: GenericRecordListView(title: "未分类", systemImage: "tray", records: store.sortedRecords.filter { $0.eventID == nil && $0.folderID == nil }, store: store)) {
                        FolderSummaryRow(title: "未分类", systemImage: "tray", count: store.sortedRecords.filter { $0.eventID == nil && $0.folderID == nil }.count)
                    }
                    NavigationLink(destination: GenericRecordListView(title: "今日拍记", systemImage: "calendar", records: store.todayRecords, store: store)) {
                        FolderSummaryRow(title: "今日拍记", systemImage: "calendar", count: store.todayRecordCount)
                    }
                    NavigationLink(destination: GenericRecordListView(title: "待处理", systemImage: "clock", records: store.sortedRecords.filter { $0.processingState == .pending }, store: store)) {
                        FolderSummaryRow(title: "待处理", systemImage: "clock", count: store.pendingRecordsCount)
                    }
                    NavigationLink(destination: GenericRecordListView(title: "回收站", systemImage: "trash", records: store.deletedRecords, store: store, isTrash: true)) {
                        FolderSummaryRow(title: "回收站", systemImage: "trash", count: store.deletedRecords.count)
                    }
                }
                
                if !store.customFolders.isEmpty {
                    Section("自建文件夹") {
                        ForEach(store.customFolders) { folder in
                            NavigationLink(destination: GenericRecordListView(title: folder.name, systemImage: "folder", records: store.sortedRecords.filter { $0.folderID == folder.id }, store: store)) {
                                FolderSummaryRow(
                                    title: folder.name,
                                    systemImage: "folder",
                                    count: store.records.filter { $0.folderID == folder.id && !$0.isDeleted }.count
                                )
                            }
                            .contextMenu {
                                Button {
                                    renameFolderName = folder.name
                                    folderToRename = folder
                                    showingRenameFolderAlert = true
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                
                                Button(role: .destructive) {
                                    folderToDelete = folder
                                    showingDeleteFolderAlert = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if !store.eventsWithRecords.isEmpty {
                    Section("课程与会议") {
                        ForEach(store.eventsWithRecords) { event in
                            NavigationLink {
                                EventDetailView(event: event, store: store)
                            } label: {
                                FolderSummaryRow(
                                    title: event.title,
                                    systemImage: "folder",
                                    count: store.records.filter { $0.eventID == event.id }.count
                                )
                            }
                        }
                    }
                }

                if displayedRecords.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "暂无记录" : "无匹配记录",
                        systemImage: searchText.isEmpty ? "book.closed" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "拍记后会在这里归档。" : "试试标题、摘要或 OCR 里的其他关键词。")
                    )
                } else {
                    Section("全部记录") {
                        ForEach(displayedRecords) { record in
                            NavigationLink {
                                RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
                            } label: {
                                RecordListRow(record: record, eventTitle: store.eventTitle(for: record))
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    store.toggleFavorite(id: record.id)
                                } label: {
                                    Label(record.isFavorite ? "取消收藏" : "收藏", systemImage: record.isFavorite ? "star.slash" : "star")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.toggleDeleted(id: record.id)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("记录")
            .searchable(text: $searchText, prompt: "搜索标题、摘要或 OCR")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        newFolderName = ""
                        showingCreateFolderAlert = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("新建文件夹")
                }
            }
            .alert("新建文件夹", isPresented: $showingCreateFolderAlert) {
                TextField("文件夹名称", text: $newFolderName)
                Button("取消", role: .cancel) { }
                Button("创建") {
                    let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        store.createFolder(name: trimmed)
                    }
                }
            }
            .alert("重命名文件夹", isPresented: $showingRenameFolderAlert) {
                TextField("文件夹名称", text: $renameFolderName)
                Button("取消", role: .cancel) { }
                Button("确定") {
                    let trimmed = renameFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let folder = folderToRename {
                        store.renameFolder(id: folder.id, newName: trimmed)
                    }
                }
            }
            .alert("删除文件夹", isPresented: $showingDeleteFolderAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    if let folder = folderToDelete {
                        store.deleteFolder(id: folder.id)
                    }
                }
            } message: {
                Text("删除此文件夹不会删除其中的拍记，它们将被移至“未分类”。")
            }
        }
    }

    private var displayedRecords: [NoteRecord] {
        store.records(matching: searchText)
    }
}

#Preview {
    RecordsView(store: NotieeStore.sample())
}

private struct FolderSummaryRow: View {
    let title: String
    let systemImage: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.medium))

            Spacer()

            Text("\(count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecordListRow: View {
    let record: NoteRecord
    let eventTitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RecordThumbnailView(record: record, size: 54, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(record.capturedAt.formatted(.dateTime.hour().minute()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(record.summary.isEmpty ? record.processingState.displayName : record.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label(eventTitle ?? "未分类", systemImage: eventTitle == nil ? "tray" : "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct GenericRecordListView: View {
    let title: String
    let systemImage: String
    var records: [NoteRecord]
    @ObservedObject var store: NotieeStore
    var isTrash: Bool = false
    
    @State private var selection = Set<UUID>()
    @Environment(\.editMode) private var editMode
    
    var body: some View {
        List(selection: $selection) {
            ForEach(records) { record in
                NavigationLink {
                    RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
                } label: {
                    RecordListRow(record: record, eventTitle: store.eventTitle(for: record))
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !isTrash {
                        Button {
                            store.toggleFavorite(id: record.id)
                        } label: {
                            Label(record.isFavorite ? "取消收藏" : "收藏", systemImage: record.isFavorite ? "star.slash" : "star")
                        }
                        .tint(.orange)
                    } else {
                        Button {
                            store.toggleDeleted(id: record.id)
                        } label: {
                            Label("恢复", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !isTrash {
                        Button(role: .destructive) {
                            store.toggleDeleted(id: record.id)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .tint(.red)
                    } else {
                        Button(role: .destructive) {
                            store.permanentlyDelete(id: record.id)
                        } label: {
                            Label("彻底删除", systemImage: "trash.fill")
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .navigationTitle(title)
        .overlay {
            if records.isEmpty {
                ContentUnavailableView(isTrash ? "回收站为空" : "暂无记录", systemImage: systemImage)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if editMode?.wrappedValue.isEditing == true {
                HStack {
                    if !isTrash {
                        Button(role: .destructive) {
                            store.toggleDeletedMultiple(ids: selection, isDeleted: true)
                            selection.removeAll()
                            editMode?.wrappedValue = .inactive
                        } label: {
                            Text("删除选中 (\(selection.count))")
                        }
                        .disabled(selection.isEmpty)
                        .foregroundColor(selection.isEmpty ? .secondary : .red)
                        .padding(.vertical, 8)
                    } else {
                        Button {
                            store.toggleDeletedMultiple(ids: selection, isDeleted: false)
                            selection.removeAll()
                            editMode?.wrappedValue = .inactive
                        } label: {
                            Text("恢复选中 (\(selection.count))")
                        }
                        .disabled(selection.isEmpty)
                        .padding(.vertical, 8)
                        
                        Spacer()
                        
                        Button(role: .destructive) {
                            store.permanentlyDeleteMultiple(ids: selection)
                            selection.removeAll()
                            editMode?.wrappedValue = .inactive
                        } label: {
                            Text("彻底删除 (\(selection.count))")
                        }
                        .disabled(selection.isEmpty)
                        .foregroundColor(selection.isEmpty ? .secondary : .red)
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
        }
    }
}
