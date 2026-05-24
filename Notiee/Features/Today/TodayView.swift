import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel
    @State private var completedCollapsed = true
    @State private var currentCollapsed = false
    @State private var upcomingCollapsed = false
    @State private var selectedTodo: NoteTodo?
    @State private var selectedEvent: ScheduledEvent?
    @State private var showCreateSheet = false

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
                            collapsed: $currentCollapsed
                        )

                        timelineStatusGroup(
                            title: "即将到来",
                            count: viewModel.upcomingEvents.count,
                            tint: .orange,
                            events: viewModel.upcomingEvents,
                            collapsed: $upcomingCollapsed
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
            .navigationDestination(for: NoteRecord.self) { record in
                if let store = viewModel.store {
                    RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
                }
            }
            .sheet(item: $selectedTodo) { todo in
                TodoDetailSheet(todo: todo, viewModel: viewModel)
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailSheet(event: event, viewModel: viewModel)
            }
            .sheet(isPresented: $showCreateSheet) {
                CreateItemSheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(viewModel.formattedDateWithWeek)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
            }
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
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ForEach(events) { event in
                        Button {
                            selectedEvent = event
                        } label: {
                            EventCard(event: event, currentDate: viewModel.currentDate, tag: viewModel.store?.customTags.first(where: { $0.id == event.tagID }))
                        }
                        .buttonStyle(.plain)
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
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(viewModel.allTodos) { todo in
                    TodoRow(todo: todo, onToggle: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleTodo(id: todo.id)
                        }
                    }, onInfo: {
                        selectedTodo = todo
                    })
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
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(viewModel.todayRecords) { record in
                    NavigationLink(value: record) {
                        RecordCard(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Event Card

private struct EventCard: View {
    let event: ScheduledEvent
    let currentDate: Date
    let tag: EventTag?

    var body: some View {
        HStack(spacing: 14) {
            // Tag badge
            Text(tag?.name ?? "普通")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(tag?.color ?? .secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var timeRange: String {
        "\(event.startDate.formatted(.dateTime.hour().minute())) - \(event.endDate.formatted(.dateTime.hour().minute()))"
    }
}

// MARK: - Todo Row

private struct TodoRow: View {
    let todo: NoteTodo
    let onToggle: () -> Void
    let onInfo: () -> Void

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
                .lineLimit(1)

            Spacer(minLength: 8)
            
            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - TodoDetailSheet

private struct TodoDetailSheet: View {
    let todo: NoteTodo
    @ObservedObject var viewModel: TodayViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedContent: String
    
    init(todo: NoteTodo, viewModel: TodayViewModel) {
        self.todo = todo
        self.viewModel = viewModel
        _editedContent = State(initialValue: todo.content)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("待办内容") {
                    TextEditor(text: $editedContent)
                        .frame(minHeight: 100)
                }
                
                Section("相关信息") {
                    LabeledContent("状态", value: todo.isCompleted ? "已完成" : "未完成")
                    if let record = viewModel.record(for: todo) {
                        LabeledContent("来源", value: record.title)
                    }
                }
            }
            .navigationTitle("待办详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        viewModel.editTodo(id: todo.id, newContent: editedContent)
                        dismiss()
                    }
                    .disabled(editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
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
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - EventDetailSheet

private struct EventDetailSheet: View {
    let event: ScheduledEvent
    @ObservedObject var viewModel: TodayViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingAddTagAlert = false
    @State private var newTagName = ""
    @State private var newTagColor = "#007AFF"
    
    let presetColors = [
        "#007AFF", // Blue
        "#FF9500", // Orange
        "#34C759", // Green
        "#AF52DE", // Purple
        "#FF3B30", // Red
        "#5856D6", // Indigo
        "#FFCC00"  // Yellow
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("日程信息") {
                    LabeledContent("标题", value: event.title)
                    LabeledContent("开始时间", value: event.startDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("结束时间", value: event.endDate.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("持续时间", value: formattedDuration(from: event.startDate, to: event.endDate))
                }
                
                Section {
                    let currentTagID = viewModel.store?.events.first(where: { $0.id == event.id })?.tagID
                    
                    if let store = viewModel.store {
                        ForEach(store.customTags) { tag in
                            Button {
                                store.assignTagToEvent(eventID: event.id, tagID: tag.id)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(tag.color)
                                        .frame(width: 16, height: 16)
                                    Text(tag.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if currentTagID == tag.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                    
                    Button("普通 (无标签)") {
                        viewModel.store?.assignTagToEvent(eventID: event.id, tagID: nil)
                    }
                    .foregroundStyle(.secondary)
                    
                } header: {
                    Text("选择标签")
                }
                
                Section {
                    Button("新建标签...") {
                        newTagName = ""
                        newTagColor = "#007AFF"
                        showingAddTagAlert = true
                    }
                }
            }
            .navigationTitle("日程详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .alert("新建标签", isPresented: $showingAddTagAlert) {
                TextField("标签名称", text: $newTagName)
                Button("取消", role: .cancel) { }
                Button("创建") {
                    if !newTagName.isEmpty {
                        viewModel.store?.createTag(name: newTagName, colorHex: newTagColor)
                        // Assign the newly created tag
                        if let newTag = viewModel.store?.customTags.last {
                            viewModel.store?.assignTagToEvent(eventID: event.id, tagID: newTag.id)
                        }
                    }
                }
            } message: {
                Text("将在下次更新中提供自选颜色 UI，目前默认使用蓝色。")
            }
        }
    }
    
    private func formattedDuration(from: Date, to: Date) -> String {
        let minutes = Int(to.timeIntervalSince(from) / 60)
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours) 小时"
            }
            return "\(hours) 小时 \(mins) 分钟"
        }
        return "\(minutes) 分钟"
    }
}



// MARK: - Preview

#Preview {
    TodayView()
}
