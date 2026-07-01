import SwiftUI

struct SparkMemoryView: View {
    @State private var memories: [MemoryEntry] = []

    var body: some View {
        List {
            Section {
                Text("这里记录了 Spark 在与你的对话中记下的信息，帮助它更好地了解你。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if memories.isEmpty {
                Section {
                    ContentUnavailableView(
                        "暂无记忆",
                        systemImage: "brain.head.profile",
                        description: Text("Spark 还没有记下关于你的信息。多和它聊聊天吧。")
                    )
                }
                .listRowBackground(Color.clear)
            } else {
                Section("共 \(memories.count) 条记忆") {
                    ForEach(memories) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.key)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(entry.value)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleteEntry(entry)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("记忆")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadMemories)
    }

    private func loadMemories() {
        let mem = (try? SparkMemoryStore.live.load()) ?? [:]
        memories = mem.map { MemoryEntry(key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }

    private func deleteEntry(_ entry: MemoryEntry) {
        var mem = (try? SparkMemoryStore.live.load()) ?? [:]
        mem.removeValue(forKey: entry.key)
        try? SparkMemoryStore.live.save(mem)
        memories.removeAll { $0.id == entry.id }
    }
}

struct MemoryEntry: Identifiable {
    let id = UUID()
    let key: String
    let value: String
}

#Preview {
    NavigationStack {
        SparkMemoryView()
    }
}
