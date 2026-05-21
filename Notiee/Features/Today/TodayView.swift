import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: TodayViewModel.sample())
    }

    @MainActor
    init(viewModel: TodayViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let currentEvent = viewModel.currentEvent {
                        CurrentEventCard(event: currentEvent, currentDate: viewModel.currentDate)
                    }

                    TodaySection(title: "今日时间轴", systemImage: "calendar") {
                        VStack(spacing: 10) {
                            ForEach(viewModel.timelineItems) { event in
                                TimelineRow(event: event, currentDate: viewModel.currentDate)
                            }
                        }
                    }

                    TodaySection(title: "待办事项", systemImage: "checklist") {
                        VStack(spacing: 10) {
                            ForEach(viewModel.pendingTodos) { todo in
                                TodoRow(todo: todo)
                            }
                        }
                    }

                    TodaySection(title: "今日记录", systemImage: "photo.on.rectangle") {
                        VStack(spacing: 12) {
                            ForEach(viewModel.todayRecords) { record in
                                RecordRow(record: record)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 132)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(viewModel.currentDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }
}

#Preview {
    TodayView()
}

private struct TodaySection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

private struct CurrentEventCard: View {
    let event: ScheduledEvent
    let currentDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("正在进行", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)

                Spacer()

                Text(timeRange)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(.title2.weight(.bold))

                Text(event.kind.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.blue.opacity(0.18), lineWidth: 1)
        }
    }

    private var timeRange: String {
        "\(event.startDate.formatted(.dateTime.hour().minute())) - \(event.endDate.formatted(.dateTime.hour().minute()))"
    }
}

private struct TimelineRow: View {
    let event: ScheduledEvent
    let currentDate: Date

    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(status.tint)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)

                Text(timeRange)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(status.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(status.tint.opacity(0.12), in: Capsule())
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var status: EventStatusPresentation {
        EventStatusPresentation(status: event.status(at: currentDate))
    }

    private var timeRange: String {
        "\(event.startDate.formatted(.dateTime.hour().minute())) - \(event.endDate.formatted(.dateTime.hour().minute()))"
    }
}

private struct TodoRow: View {
    let todo: NoteTodo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(todo.content)
                .font(.body.weight(.medium))

            Spacer()
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct RecordRow: View {
    let record: NoteRecord

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.secondary.opacity(0.14))
                .frame(width: 58, height: 58)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(record.title)
                        .font(.headline)

                    Spacer()

                    Text(record.capturedAt.formatted(.dateTime.hour().minute()))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(record.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Label(record.processingState.displayName, systemImage: record.processingState.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.processingState.tint)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct EventStatusPresentation {
    let title: String
    let tint: Color

    init(status: ScheduledEvent.Status) {
        switch status {
        case .completed:
            title = "已完成"
            tint = .secondary
        case .current:
            title = "进行中"
            tint = .blue
        case .upcoming:
            title = "即将到来"
            tint = .green
        }
    }
}

private extension ScheduledEvent.Kind {
    var displayName: String {
        switch self {
        case .course:
            return "课程"
        case .meeting:
            return "会议"
        case .uncategorized:
            return "未分类"
        }
    }
}

private extension AIProcessingState {
    var displayName: String {
        switch self {
        case .pending:
            return "等待处理"
        case .processing:
            return "AI 处理中"
        case .completed:
            return "已生成摘要"
        case .failed:
            return "处理失败"
        }
    }

    var symbolName: String {
        switch self {
        case .pending:
            return "clock"
        case .processing:
            return "sparkles"
        case .completed:
            return "checkmark.circle"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .pending:
            return .secondary
        case .processing:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
}
