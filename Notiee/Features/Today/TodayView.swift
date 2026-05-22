import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel
    @State private var completedCollapsed = true

    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: TodayViewModel.sample())
    }

    @MainActor
    init(store: NotieeStore) {
        _viewModel = StateObject(wrappedValue: TodayViewModel(store: store))
    }

    @MainActor
    init(viewModel: TodayViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MARK: - Header
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 20)

                    // MARK: - Timeline
                    VStack(alignment: .leading, spacing: 16) {
                        timelineStatusGroup(
                            title: "已完成",
                            count: viewModel.completedEvents.count,
                            tint: .secondary,
                            events: viewModel.completedEvents,
                            collapsed: $completedCollapsed
                        )

                        timelineStatusGroup(
                            title: "正在进行",
                            count: viewModel.currentEvents.count,
                            tint: .green,
                            events: viewModel.currentEvents,
                            collapsed: .constant(false)
                        )

                        timelineStatusGroup(
                            title: "即将到来",
                            count: viewModel.upcomingEvents.count,
                            tint: .orange,
                            events: viewModel.upcomingEvents,
                            collapsed: .constant(false)
                        )
                    }
                    .padding(.horizontal, 20)

                    // MARK: - BottomSheet Drag Handle
                    dragHandle
                        .padding(.top, 28)
                        .padding(.bottom, 20)

                    // MARK: - 待办事项
                    todoSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    // MARK: - 今日记录
                    recordsSection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)
                }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(viewModel.formattedDateWithWeek)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Timeline Status Group

    private func timelineStatusGroup(
        title: String,
        count: Int,
        tint: Color,
        events: [ScheduledEvent],
        collapsed: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Section header with count badge
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    collapsed.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(tint, in: Circle())

                    Spacer()

                    if count > 0 {
                        Image(systemName: collapsed.wrappedValue ? "chevron.right" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Event cards
            if !collapsed.wrappedValue {
                if events.isEmpty {
                    // "无事件" empty state
                    Text("无事件")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ForEach(events) { event in
                        EventCard(event: event, currentDate: viewModel.currentDate)
                    }
                }
            }
        }
    }

    // MARK: - Drag Handle

    private var dragHandle: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color(.systemFill))
                .frame(width: 40, height: 5)
            Spacer()
        }
    }

    // MARK: - Todo Section

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("待办事项")
                    .font(.title3.weight(.bold))

                Text("\(viewModel.pendingTodos.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.blue, in: Circle())
            }

            if viewModel.allTodos.isEmpty {
                Text("AI 提取的待办会显示在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(viewModel.allTodos) { todo in
                    TodoRow(todo: todo) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleTodo(id: todo.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Records Section

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("今日记录")
                    .font(.title3.weight(.bold))

                Text("\(viewModel.todayRecords.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.orange, in: Circle())
            }

            if viewModel.todayRecords.isEmpty {
                Text("拍记后会在这里展示今日的记录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(viewModel.todayRecords) { record in
                    RecordCard(record: record)
                }
            }
        }
    }
}

// MARK: - Event Card

private struct EventCard: View {
    let event: ScheduledEvent
    let currentDate: Date

    var body: some View {
        HStack(spacing: 14) {
            // Kind badge
            Text(event.kind.shortLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(event.kind.badgeColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(timeRange)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var timeRange: String {
        "\(event.startDate.formatted(.dateTime.hour().minute())) - \(event.endDate.formatted(.dateTime.hour().minute()))"
    }
}

// MARK: - Todo Row

private struct TodoRow: View {
    let todo: NoteTodo
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(todo.content)
                .font(.body.weight(.medium))
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)

            Spacer(minLength: 8)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Record Card

private struct RecordCard: View {
    let record: NoteRecord

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RecordThumbnailView(record: record, size: 72, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 6) {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(1)

                if !record.summary.isEmpty {
                    Text(record.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Label(record.processingState.displayName, systemImage: record.processingState.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(record.processingState.tint)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Model Extensions

private extension ScheduledEvent.Kind {
    var shortLabel: String {
        switch self {
        case .course: "课程"
        case .meeting: "会议"
        case .uncategorized: "其他"
        }
    }

    var badgeColor: Color {
        switch self {
        case .course: .orange
        case .meeting: .blue
        case .uncategorized: .secondary
        }
    }
}



// MARK: - Preview

#Preview {
    TodayView()
}
