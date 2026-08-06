import SwiftUI

struct RecordsView: View {
    @ObservedObject private var store: NotieeStore
    @ObservedObject private var appLock = AppLockManager.shared
    @State private var pendingDelete: PendingAuthDelete?
    @State private var searchText = ""

    @State private var showingCreateFolderAlert = false
    @State private var newFolderName = ""

    @State private var showingNewTextRecord = false

    @State private var showingRenameFolderAlert = false
    @State private var folderToRename: CustomFolder?
    @State private var renameFolderName = ""

    @State private var showingDeleteFolderAlert = false
    @State private var folderToDelete: CustomFolder?

    @State private var isSystemFolderExpanded = true
    @State private var isCustomFolderExpanded = true
    @State private var isEventFolderExpanded = true

    enum SystemFolderType: String, Identifiable {
        case favorites, unclassified, today, pending, trash
        var id: String { rawValue }
    }
    @State private var selectedSystemFolder: SystemFolderType?

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
                Section(header: HStack {
                    Text("系统文件夹")
                    Spacer()
                    Image(systemName: isSystemFolderExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation { isSystemFolderExpanded.toggle() }
                }) {
                    if isSystemFolderExpanded {
                        HStack(spacing: 0) {
                            Button { selectedSystemFolder = .favorites } label: {
                                SystemFolderIcon(title: "收藏夹", systemImage: "star.fill", count: store.favoriteRecords.count, tint: .yellow)
                            }
                            
                            Button { selectedSystemFolder = .unclassified } label: {
                                SystemFolderIcon(title: "未分类", systemImage: "tray", count: store.sortedRecords.filter { $0.eventID == nil && $0.folderID == nil }.count, tint: .blue)
                            }
                            
                            Button { selectedSystemFolder = .today } label: {
                                SystemFolderIcon(title: "今日拍记", systemImage: "calendar", count: store.todayRecordCount, tint: .teal)
                            }
                            
                            Button { selectedSystemFolder = .pending } label: {
                                SystemFolderIcon(title: "待处理", systemImage: "clock", count: store.pendingRecordsCount, tint: .orange)
                            }
                            
                            Button { selectedSystemFolder = .trash } label: {
                                SystemFolderIcon(title: "回收站", systemImage: "trash", count: store.deletedRecords.count, tint: .gray)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 16))
                        .buttonStyle(.plain)
                    }
                }

                if !userCustomFolders.isEmpty {
                    Section(header: HStack {
                        Text("自建文件夹")
                        Spacer()
                        Image(systemName: isCustomFolderExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { isCustomFolderExpanded.toggle() }
                    }) {
                        if isCustomFolderExpanded {
                            ForEach(userCustomFolders) { folder in
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
                }

                if !store.eventsWithRecords.isEmpty || store.nottiFolder != nil {
                    Section(header: HStack {
                        Text("日程文件夹")
                        Spacer()
                        Image(systemName: isEventFolderExpanded ? "chevron.down" : "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { isEventFolderExpanded.toggle() }
                    }) {
                        if isEventFolderExpanded {
                            if let nottiFolder = store.nottiFolder {
                                NavigationLink {
                                    GenericRecordListView(
                                        title: nottiFolder.name,
                                        systemImage: "sparkles",
                                        records: store.sortedRecords.filter { $0.folderID == nottiFolder.id },
                                        store: store
                                    )
                                } label: {
                                    FolderSummaryRow(
                                        title: nottiFolder.name,
                                        systemImage: "sparkles",
                                        count: store.records.filter { $0.folderID == nottiFolder.id && !$0.isDeleted }.count
                                    )
                                }
                            }
                            ForEach(store.eventsWithRecords) { event in
                                NavigationLink {
                                    EventDetailView(event: event, store: store)
                                } label: {
                                    FolderSummaryRow(
                                        title: event.title,
                                        systemImage: "calendar",
                                        count: store.records.filter { $0.eventID == event.id }.count
                                    )
                                }
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
                                RecordListRow(record: record, eventTitle: store.eventTitle(for: record), dateText: store.formattedDateWithWeek(for: record.capturedAt), searchText: searchText)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    store.toggleFavorite(id: record.id)
                                } label: {
                                    Label(record.isFavorite ? "取消收藏" : "收藏", systemImage: record.isFavorite ? "star.slash" : "star")
                                }
                                .tint(.orange)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: !appLock.shouldAuthForDeleting(record)) {
                                if appLock.shouldAuthForDeleting(record) {
                                    // Non-destructive role: avoid SwiftUI's optimistic row removal,
                                    // since the actual delete only happens after auth succeeds.
                                    Button {
                                        requestDelete(record) { store.toggleDeleted(id: record.id) }
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    .tint(.red)
                                } else {
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
            }
            .deleteAuthSheet($pendingDelete, lock: appLock)
            .navigationTitle("记录")
            .searchable(text: $searchText, prompt: "搜索标题、摘要或 OCR")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showingNewTextRecord = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("新建纯文字记录")

                        Button {
                            newFolderName = ""
                            showingCreateFolderAlert = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityLabel("新建文件夹")
                    }
                }
            }
            .sheet(isPresented: $showingNewTextRecord) {
                NewTextRecordSheet(store: store)
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
            .navigationDestination(item: $selectedSystemFolder) { folderType in
                switch folderType {
                case .favorites:
                    GenericRecordListView(title: "收藏夹", systemImage: "star.fill", records: store.favoriteRecords, store: store)
                case .unclassified:
                    GenericRecordListView(title: "未分类", systemImage: "tray", records: store.sortedRecords.filter { $0.eventID == nil && $0.folderID == nil }, store: store)
                case .today:
                    GenericRecordListView(title: "今日拍记", systemImage: "calendar", records: store.todayRecords, store: store)
                case .pending:
                    GenericRecordListView(title: "待处理", systemImage: "clock", records: store.sortedRecords.filter { $0.processingState == .pending }, store: store)
                case .trash:
                    GenericRecordListView(title: "回收站", systemImage: "trash", records: store.deletedRecords, store: store, isTrash: true)
                }
            }
        }
    }

    private var userCustomFolders: [CustomFolder] {
        store.customFolders.filter {
            $0.systemRole != .nottiGenerated && $0.name != FolderTagManager.nottiFolderName
        }
    }

    private var displayedRecords: [NoteRecord] {
        store.records(matching: searchText)
    }

    private func requestDelete(_ record: NoteRecord, _ action: @escaping () -> Void) {
        if appLock.shouldAuthForDeleting(record) {
            pendingDelete = PendingAuthDelete(count: 1, perform: action)
        } else {
            action()
        }
    }
}

/// A pending delete that must pass identity verification before running.
struct PendingAuthDelete: Identifiable {
    let id = UUID()
    let count: Int
    let perform: () -> Void
}

extension View {
    /// Presents the passcode/biometric gate for a pending encrypted-record deletion.
    func deleteAuthSheet(_ item: Binding<PendingAuthDelete?>, lock: AppLockManager) -> some View {
        sheet(item: item) { pending in
            PasscodeUnlockView(
                lock: lock,
                title: "验证以删除",
                subtitle: pending.count > 1 ? "删除 \(pending.count) 条加密拍记需验证身份" : "删除加密拍记需要验证身份",
                reason: "删除加密拍记",
                onAuthenticated: {
                    pending.perform()
                    item.wrappedValue = nil
                },
                onCancel: { item.wrappedValue = nil }
            )
        }
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
    let dateText: String
    var searchText: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RecordThumbnailView(record: record, size: 54, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    HighlightedText(text: record.title, query: searchText, font: .headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(dateText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if record.isEncrypted {
                    Label("已加密拍记", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    let summaryText = record.summary.isEmpty ? record.processingState.displayName : record.summary
                    HighlightedText(text: summaryText, query: searchText, font: .subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    Image(systemName: eventTitle == nil ? "tray" : "calendar")
                    Text(eventTitle ?? "未分类")
                }
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

    @ObservedObject private var appLock = AppLockManager.shared
    @State private var pendingDelete: PendingAuthDelete?
    @State private var selection = Set<UUID>()
    @Environment(\.editMode) private var editMode

    var body: some View {
        List(selection: $selection) {
            ForEach(records) { record in
                NavigationLink {
                    RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
                } label: {
                    RecordListRow(record: record, eventTitle: store.eventTitle(for: record), dateText: store.formattedDateWithWeek(for: record.capturedAt))
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
                .swipeActions(edge: .trailing, allowsFullSwipe: !appLock.shouldAuthForDeleting(record)) {
                    if appLock.shouldAuthForDeleting(record) {
                        // Non-destructive role: defer removal until auth succeeds so the
                        // row isn't optimistically hidden by SwiftUI.
                        Button {
                            requestDelete([record]) {
                                if isTrash { store.permanentlyDelete(id: record.id) }
                                else { store.toggleDeleted(id: record.id) }
                            }
                        } label: {
                            Label(isTrash ? "彻底删除" : "删除", systemImage: isTrash ? "trash.fill" : "trash")
                        }
                        .tint(.red)
                    } else if !isTrash {
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
        .deleteAuthSheet($pendingDelete, lock: appLock)
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
                            let ids = selection
                            requestDeleteMultiple(ids) {
                                store.toggleDeletedMultiple(ids: ids, isDeleted: true)
                                selection.removeAll()
                                editMode?.wrappedValue = .inactive
                            }
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
                            let ids = selection
                            requestDeleteMultiple(ids) {
                                store.permanentlyDeleteMultiple(ids: ids)
                                selection.removeAll()
                                editMode?.wrappedValue = .inactive
                            }
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

    private func requestDelete(_ recordsToDelete: [NoteRecord], _ action: @escaping () -> Void) {
        if recordsToDelete.contains(where: { appLock.shouldAuthForDeleting($0) }) {
            pendingDelete = PendingAuthDelete(count: recordsToDelete.count, perform: action)
        } else {
            action()
        }
    }

    private func requestDeleteMultiple(_ ids: Set<UUID>, _ action: @escaping () -> Void) {
        let encrypted = records.filter { ids.contains($0.id) && appLock.shouldAuthForDeleting($0) }
        if encrypted.isEmpty {
            action()
        } else {
            pendingDelete = PendingAuthDelete(count: encrypted.count, perform: action)
        }
    }
}

private struct SystemFolderIcon: View {
    let title: String
    let systemImage: String
    let count: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.13), in: Circle())
                
                if count > 0 {
                    Text("\(count > 99 ? "99+" : "\(count)")")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(tint.opacity(0.3), lineWidth: 1)
                        )
                        .offset(x: 8, y: -4)
                }
            }

            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
