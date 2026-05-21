import SwiftUI

struct RecordsView: View {
    @ObservedObject private var store: NotieeStore
    @State private var searchText = ""

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
                    FolderSummaryRow(title: "未分类", systemImage: "tray", count: store.uncategorizedCount)
                    FolderSummaryRow(title: "今日拍记", systemImage: "calendar", count: store.todayRecordCount)
                    FolderSummaryRow(title: "待处理", systemImage: "clock", count: store.pendingRecordsCount)
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
                        }
                    }
                }
            }
            .navigationTitle("记录")
            .searchable(text: $searchText, prompt: "搜索标题、摘要或 OCR")
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

private struct RecordListRow: View {
    let record: NoteRecord
    let eventTitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(record.processingState.tint.opacity(0.14))
                .frame(width: 54, height: 54)
                .overlay {
                    Image(systemName: record.processingState.symbolName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(record.processingState.tint)
                }

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

private extension AIProcessingState {
    var displayName: String {
        switch self {
        case .pending:
            "等待 AI 处理"
        case .processing:
            "AI 处理中"
        case .completed:
            "已生成摘要"
        case .failed:
            "处理失败"
        }
    }

    var symbolName: String {
        switch self {
        case .pending:
            "clock"
        case .processing:
            "sparkles"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .pending:
            .orange
        case .processing:
            .blue
        case .completed:
            .green
        case .failed:
            .red
        }
    }
}
