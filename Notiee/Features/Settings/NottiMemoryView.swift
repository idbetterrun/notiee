import SwiftUI

struct NottiMemoryView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case active
        case pending
        case archived

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .active: "使用中"
            case .pending: "待确认"
            case .archived: "已归档"
            }
        }
    }

    @AppStorage(UDK.nottiAutomaticMemoryEnabled) private var automaticMemoryEnabled = true
    @AppStorage(UDK.nottiMemoryUseEnabled) private var memoryUseEnabled = true

    @State private var memories: [NottiMemory] = []
    @State private var pending: [NottiPendingMemory] = []
    @State private var scope: Scope = .active
    @State private var searchText = ""
    @State private var category: NottiMemoryCategory?
    @State private var editingMemory: NottiMemory?
    @State private var editText = ""
    @State private var showsClearConfirmation = false
    @State private var errorMessage: String?

    private let repository: NottiMemoryRepository

    init(repository: NottiMemoryRepository = .live) {
        self.repository = repository
    }

    var body: some View {
        List {
            Section {
                Toggle("自动记住有用信息", isOn: $automaticMemoryEnabled)
                Toggle("在回答中使用记忆", isOn: $memoryUseEnabled)
            } footer: {
                Text("关闭不会删除已有记忆。记忆库只保存在本机，命中的少量内容会临时发送给所选 AI 模型。")
            }

            Section {
                Picker("状态", selection: $scope) {
                    ForEach(Scope.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let errorMessage {
                Section {
                    ContentUnavailableView(
                        "记忆暂不可用",
                        systemImage: "exclamationmark.lock",
                        description: Text(errorMessage)
                    )
                }
                .listRowBackground(Color.clear)
            } else if scope == .pending {
                pendingContent
            } else {
                memoryContent
            }
        }
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索记忆")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                categoryMenu
                if !memories.isEmpty {
                    ShareLink(item: exportText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("导出记忆")
                }
                Button(role: .destructive) {
                    showsClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(memories.isEmpty && pending.isEmpty)
                .accessibilityLabel("清空全部记忆")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editingMemory) { memory in
            NavigationStack {
                Form {
                    TextEditor(text: $editText)
                        .frame(minHeight: 160)
                }
                .navigationTitle("编辑记忆")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { editingMemory = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { saveEdit(memory) }
                            .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .alert("清空全部记忆？", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("永久清空", role: .destructive) { clearAll() }
        } message: {
            Text("正文、修订记录、关联和本地向量都会被永久删除，此操作无法撤销。")
        }
    }

    @ViewBuilder
    private var memoryContent: some View {
        if filteredMemories.isEmpty {
            Section {
                ContentUnavailableView(
                    scope == .active ? "暂无记忆" : "暂无归档记忆",
                    systemImage: "brain.head.profile",
                    description: Text(scope == .active ? "与 Notti 对话后，有用的信息会出现在这里。" : "过期或手动归档的记忆会出现在这里。")
                )
            }
            .listRowBackground(Color.clear)
        } else {
            Section("共 \(filteredMemories.count) 条") {
                ForEach(filteredMemories) { memory in
                    memoryRow(memory)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { delete(memory) } label: {
                                Label("永久删除", systemImage: "trash")
                            }
                            if scope == .active {
                                Button { archive(memory) } label: {
                                    Label("归档", systemImage: "archivebox")
                                }
                                .tint(.orange)
                            } else {
                                Button { restore(memory) } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            }
                        }
                        .contextMenu {
                            Button {
                                editText = memory.text
                                editingMemory = memory
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var pendingContent: some View {
        let filtered = filteredPending
        if filtered.isEmpty {
            Section {
                ContentUnavailableView(
                    "没有待确认项",
                    systemImage: "checkmark.shield",
                    description: Text("敏感信息只有在你确认后才会成为可用记忆。")
                )
            }
            .listRowBackground(Color.clear)
        } else {
            Section("共 \(filtered.count) 条") {
                ForEach(filtered) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.proposal.text)
                        Label("包含敏感信息", systemImage: "hand.raised.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        HStack {
                            Button("不保存", role: .destructive) { reject(item) }
                            Spacer()
                            Button("确认保存") { confirm(item) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func memoryRow(_ memory: NottiMemory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(memory.text)
                .font(.body)
            HStack(spacing: 10) {
                Label(memory.category.localizedName, systemImage: memory.category.systemImage)
                Text(memory.durability.localizedName)
                if memory.evidenceCount > 1 {
                    Text("提及 \(memory.evidenceCount) 次")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private var categoryMenu: some View {
        Menu {
            Button {
                category = nil
            } label: {
                if category == nil { Label("全部分类", systemImage: "checkmark") }
                else { Text("全部分类") }
            }
            ForEach(NottiMemoryCategory.allCases, id: \.self) { item in
                Button {
                    category = item
                } label: {
                    if category == item { Label(item.localizedName, systemImage: "checkmark") }
                    else { Text(item.localizedName) }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("筛选分类")
    }

    private var filteredMemories: [NottiMemory] {
        memories.filter { memory in
            let scopeMatches: Bool
            switch scope {
            case .active: scopeMatches = [.active, .provisional].contains(memory.status)
            case .pending: scopeMatches = false
            case .archived: scopeMatches = [.archived, .expired, .superseded, .merged].contains(memory.status)
            }
            let categoryMatches = category == nil || memory.category == category
            let queryMatches = searchText.isEmpty || memory.text.localizedCaseInsensitiveContains(searchText) ||
                memory.topicKey.localizedCaseInsensitiveContains(searchText)
            return scopeMatches && categoryMatches && queryMatches
        }
    }

    private var filteredPending: [NottiPendingMemory] {
        pending.filter { item in
            (category == nil || item.proposal.category == category) &&
            (searchText.isEmpty || item.proposal.text.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var exportText: String {
        memories.sorted { $0.updatedAt > $1.updatedAt }.map { memory in
            "[\(memory.category.rawValue)] \(memory.text)"
        }.joined(separator: "\n")
    }

    @MainActor
    private func load() async {
        do {
            memories = try await repository.allMemories()
            pending = try await repository.pendingMemories()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        Task { await load() }
    }

    private func saveEdit(_ memory: NottiMemory) {
        let text = editText
        editingMemory = nil
        Task {
            try? await repository.edit(id: memory.id, text: text)
            await load()
        }
    }

    private func archive(_ memory: NottiMemory) {
        Task {
            try? await repository.setStatus(id: memory.id, status: .archived)
            await load()
        }
    }

    private func restore(_ memory: NottiMemory) {
        Task {
            try? await repository.setStatus(id: memory.id, status: .active)
            await load()
        }
    }

    private func delete(_ memory: NottiMemory) {
        Task {
            try? await repository.hardDelete(id: memory.id)
            await load()
        }
    }

    private func confirm(_ item: NottiPendingMemory) {
        Task {
            _ = try? await repository.confirmPending(id: item.id)
            await load()
        }
    }

    private func reject(_ item: NottiPendingMemory) {
        Task {
            try? await repository.rejectPending(id: item.id)
            await load()
        }
    }

    private func clearAll() {
        Task {
            try? await repository.clearAll()
            await load()
        }
    }
}

private extension NottiMemoryCategory {
    var localizedName: String {
        switch self {
        case .profile: String(localized: "画像")
        case .preference: String(localized: "偏好")
        case .relationship: String(localized: "关系")
        case .event: String(localized: "事件")
        case .plan: String(localized: "计划")
        case .state: String(localized: "状态")
        case .pattern: String(localized: "模式")
        }
    }

    var systemImage: String {
        switch self {
        case .profile: "person.crop.circle"
        case .preference: "heart"
        case .relationship: "person.2"
        case .event: "calendar"
        case .plan: "list.bullet.clipboard"
        case .state: "waveform.path.ecg"
        case .pattern: "point.3.connected.trianglepath.dotted"
        }
    }
}

private extension NottiMemoryDurability {
    var localizedName: String {
        switch self {
        case .durable: String(localized: "长期")
        case .stable: String(localized: "稳定")
        case .episodic: String(localized: "阶段")
        case .transient: String(localized: "短期")
        }
    }
}

#Preview {
    NavigationStack { NottiMemoryView() }
}
