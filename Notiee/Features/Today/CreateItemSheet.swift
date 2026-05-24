import SwiftUI
import UserNotifications

enum CreateItemType: String, CaseIterable {
    case schedule
    case todo

    var title: String {
        switch self {
        case .schedule: return "日程"
        case .todo: return "待办事项"
        }
    }
}

enum RepeatType: String, CaseIterable, Identifiable {
    case never
    case daily
    case weekly
    case biweekly
    case monthly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .never: return "永不"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .biweekly: return "每两周"
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }

    func generateDates(from start: Date, to end: Date) -> [Date] {
        var dates: [Date] = []
        let calendar = Calendar.current
        var current = start
        while current < end {
            dates.append(current)
            guard let next = nextDate(from: current, using: calendar) else { break }
            current = next
        }
        return dates
    }

    private func nextDate(from date: Date, using calendar: Calendar) -> Date? {
        switch self {
        case .never: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .biweekly: return calendar.date(byAdding: .weekOfYear, value: 2, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        case .yearly: return calendar.date(byAdding: .year, value: 1, to: date)
        }
    }
}

struct CreateItemSheet: View {
    @ObservedObject var viewModel: TodayViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var itemType: CreateItemType = .schedule

    @State private var scheduleTitle = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var repeatType: RepeatType = .never
    @State private var selectedTagID: UUID?
    @State private var notes = ""
    @State private var scheduleRepeatUntil = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    @State private var todoTitle = ""
    @State private var hasDueDate: Bool = false
    @State private var todoDueDate: Date = Date()
    @State private var hasReminder: Bool = false
    
    @State private var showTagEditSheet = false

    private let repeatEndDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $itemType) {
                        ForEach(CreateItemType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if itemType == .schedule {
                    scheduleForm
                } else {
                    todoForm
                }

                Section {
                    Button("创建") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .navigationTitle("新建")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showTagEditSheet) {
                if let store = viewModel.store {
                    TagEditSheet(store: store)
                }
            }
        }
    }

    private var canSave: Bool {
        switch itemType {
        case .schedule:
            return !scheduleTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .todo:
            return !todoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    // MARK: - Schedule Form

    private var scheduleForm: some View {
        Group {
            Section("日程信息") {
                TextField("日程标题", text: $scheduleTitle)
                    .textInputAutocapitalization(.words)

                DatePicker("开始时间", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                DatePicker("结束时间", selection: $endDate, in: startDate..., displayedComponents: [.date, .hourAndMinute])

                Picker("重复", selection: $repeatType) {
                    ForEach(RepeatType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
            }

            if let store = viewModel.store, !store.customTags.isEmpty {
                Section("标签") {
                    ForEach(store.customTags) { tag in
                        Button {
                            selectedTagID = tag.id
                        } label: {
                            HStack {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 16, height: 16)
                                Text(tag.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedTagID == tag.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                    Button("无标签") {
                        selectedTagID = nil
                    }
                    .foregroundStyle(.secondary)
                    
                    Button {
                        showTagEditSheet = true
                    } label: {
                        Label("新建标签", systemImage: "plus")
                    }
                    .foregroundStyle(.blue)
                }
            }

            Section("备注") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
            }
        }
    }

    // MARK: - Todo Form

    private var todoForm: some View {
        Group {
            Section("待办信息") {
                TextField("待办事项标题", text: $todoTitle)
                    .textInputAutocapitalization(.sentences)
            }

            Section {
                Toggle("设定日期与时间", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("截止时间", selection: $todoDueDate, displayedComponents: [.date, .hourAndMinute])
                }
            }

            Section {
                Toggle("到期提醒", isOn: $hasReminder)
                if hasReminder && !hasDueDate {
                    Text("请先设定日期与时间")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        switch itemType {
        case .schedule:
            saveSchedule()
        case .todo:
            saveTodo()
        }
    }

    private func saveSchedule() {
        guard let store = viewModel.store else { return }
        let title = scheduleTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        let duration = endDate.timeIntervalSince(startDate)

        if repeatType == .never {
            let event = ScheduledEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                kind: .course,
                tagID: selectedTagID
            )
            store.addEvent(event)
        } else {
            let eventEndDate = repeatType == .never ? endDate : max(endDate, scheduleRepeatUntil)
            let dates = repeatType.generateDates(from: startDate, to: eventEndDate)

            for date in dates {
                let eventStart = date
                let eventEnd = date.addingTimeInterval(duration)
                let event = ScheduledEvent(
                    title: title,
                    startDate: eventStart,
                    endDate: eventEnd,
                    kind: .course,
                    tagID: selectedTagID
                )
                store.addEvent(event)
            }
        }

        dismiss()
    }

    private func saveTodo() {
        guard let store = viewModel.store else { return }
        let content = todoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let dueDate = hasDueDate ? todoDueDate : nil
        let reminder = hasReminder && hasDueDate

        store.addStandaloneTodo(content: content, dueDate: dueDate, hasReminder: reminder)

        if hasReminder, let dueDate = dueDate {
            let center = UNUserNotificationCenter.current()
            let content = UNMutableNotificationContent()
            content.title = "待办提醒"
            content.body = todoTitle
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            center.add(request)
        }

        dismiss()
    }
}
