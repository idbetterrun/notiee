import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel: TodayViewModel
    @State private var completedCollapsed = true
    @State private var currentCollapsed = false
    @State private var upcomingCollapsed = false
    @State private var selectedTodo: NoteTodo?
    @State private var selectedEvent: ScheduledEvent?
    @State private var specialEvents: [SpecialDayEvent] = []
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let store = viewModel.store {
                        NavigationLink {
                            MeView(settingsStore: UserDefaultsAppSettingsStore.live, store: store)
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                        .tint(NotieeColors.themed(.blue))
                    }

                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(NotieeColors.themed(.blue))
                }
            }
            .navigationDestination(for: NoteRecord.self) { record in
                if let store = viewModel.store {
                    RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
                }
            }
            .sheet(item: $selectedTodo) { todo in
                TodoDetailSheetView(todo: todo, viewModel: viewModel)
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailSheetView(event: event, viewModel: viewModel)
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
                
                if !specialEvents.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(specialEvents) { event in
                            Text(event.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(event.color)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(event.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            Spacer()
        }
        .onAppear {
            specialEvents = CalendarService.shared.specialDayEvents(for: viewModel.currentDate)
        }
        .onChange(of: viewModel.currentDate) { _, newDate in
            specialEvents = CalendarService.shared.specialDayEvents(for: newDate)
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
                            EventCardView(
                                event: event,
                                currentDate: viewModel.currentDate,
                                tag: viewModel.store?.customTags.first(where: { $0.id == event.tagID }),
                                isLiveActive: LiveActivityManager.shared.activeEventUUID == event.id,
                                showLiveToggle: event.status(at: viewModel.currentDate) == .current && !event.isAllDay,
                                onToggleLive: {
                                    viewModel.store?.toggleLiveActivityForEvent(event.id)
                                }
                            )
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
                    TodoRowView(todo: todo, onToggle: {
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
                        RecordCardView(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Event Card

// MARK: - Todo Row

// MARK: - Record Card

// MARK: - EventDetailSheet

// MARK: - Preview

#Preview {
    TodayView()
}
