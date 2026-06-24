import SwiftUI

// MARK: - Date Group

struct DateGroup: Identifiable {
    let id = UUID()
    let date: Date
    let conversations: [SavedConversation]
    var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return String(localized: "今天") }
        if cal.isDateInYesterday(date) { return String(localized: "昨天") }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = false
        return formatter.string(from: date)
    }
}

// MARK: - History View

struct SparkHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = HistoryViewModel()
    var onSelect: (SavedConversation) -> Void

    @State private var editMode: EditMode = .inactive
    @State private var selectedIDs: Set<UUID> = []
    @State private var searchText = ""

    private var visibleGroups: [DateGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.groups }
        return store.groups.compactMap { group in
            let matched = group.conversations.filter { conv in
                conv.title.lowercased().contains(q)
                || conv.messages.contains { $0.content.lowercased().contains(q) }
            }
            return matched.isEmpty ? nil : DateGroup(date: group.date, conversations: matched)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("加载中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedIDs) {
                        if visibleGroups.isEmpty {
                            emptyView
                        }
                        ForEach(visibleGroups) { group in
                            Section(group.label) {
                                ForEach(group.conversations) { conv in
                                    Button {
                                        if editMode == .active { return }
                                        onSelect(conv)
                                        dismiss()
                                    } label: {
                                        conversationRow(conv)
                                    }
                                    .buttonStyle(.plain)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            store.delete([conv.id])
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("历史对话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editMode == .active {
                        Button("全选") {
                            selectedIDs = Set(store.conversations.map(\.id))
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if editMode == .active, !selectedIDs.isEmpty {
                            Button(role: .destructive) {
                                store.delete(selectedIDs)
                                selectedIDs = []
                                editMode = .inactive
                            } label: {
                                Text("删除 (\(selectedIDs.count))")
                            }
                        }
                        Button(editMode == .active ? "完成" : "选择") {
                            withAnimation {
                                editMode = editMode == .active ? .inactive : .active
                                if editMode == .inactive { selectedIDs = [] }
                            }
                        }
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    if editMode == .active, !selectedIDs.isEmpty {
                        Button(role: .destructive) {
                            store.delete(selectedIDs)
                            selectedIDs = []
                            editMode = .inactive
                        } label: {
                            Label("删除所选", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .searchable(text: $searchText, prompt: "搜索标题或对话内容")
            .onAppear { store.load() }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("暂无历史对话")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowBackground(Color.clear)
    }

    private func conversationRow(_ conv: SavedConversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(conv.title)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
            HStack {
                Text(conv.lastMessageAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(String(format: String(localized: "%lld 条消息"), conv.messageCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - History ViewModel

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var conversations: [SavedConversation] = []
    @Published var groups: [DateGroup] = []
    @Published var isLoading = false
    private let store = SparkHistoryStore.live

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let result = (try? store.loadConversations()) ?? []
            await MainActor.run {
                self.conversations = result
                self.groups = Self.groupByDate(result)
                self.isLoading = false
            }
        }
    }

    func delete(_ ids: Set<UUID>) {
        conversations.removeAll { ids.contains($0.id) }
        groups = Self.groupByDate(conversations)
        try? SparkConversationRepository.live.deleteFromHistory(ids)
    }

    private static func groupByDate(_ conversations: [SavedConversation]) -> [DateGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: conversations) { conv in
            cal.startOfDay(for: conv.lastMessageAt)
        }
        return dict
            .map { DateGroup(date: $0.key, conversations: $0.value.sorted { $0.lastMessageAt > $1.lastMessageAt }) }
            .sorted { $0.date > $1.date }
    }
}

#Preview {
    SparkHistoryView(onSelect: { _ in })
}
