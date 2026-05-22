import SwiftUI

struct RecordDetailView: View {
    @ObservedObject private var viewModel: RecordDetailViewModel
    @State private var loadedImage: UIImage? = nil

    init(viewModel: RecordDetailViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                imagePreview
                summarySection
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
        .onAppear {
            Task.detached(priority: .userInitiated) {
                if let img = await MainActor.run(body: { LocalImageStore.shared.loadImage(path: viewModel.record.localImagePath) }) {
                    await MainActor.run { self.loadedImage = img }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
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
        
                            Text(viewModel.record.localImagePath)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 24)
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
        DetailSection(title: "AI 摘要", systemImage: "sparkles") {
            Text(viewModel.summaryText)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var todoSection: some View {
        DetailSection(title: "待办事项", systemImage: "checklist") {
            if viewModel.todos.isEmpty {
                Text("AI 提取出的行动项会显示在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 12) {
                    ForEach(viewModel.todos) { todo in
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    viewModel.toggleTodo(id: todo.id)
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
                    }
                }
            }
        }
    }

    private var ocrSection: some View {
        DetailSection(title: "OCR 原文", systemImage: "text.viewfinder") {
            Text(viewModel.ocrText)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.secondary)

            content
                .padding(18)
                .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}



#Preview {
    let store = NotieeStore.sample()
    return NavigationStack {
        RecordDetailView(viewModel: RecordDetailViewModel(record: store.sortedRecords[0], store: store))
    }
}
