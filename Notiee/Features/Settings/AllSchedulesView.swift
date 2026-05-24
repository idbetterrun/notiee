import SwiftUI

struct AllSchedulesView: View {
    @ObservedObject var store: NotieeStore
    
    @State private var showingActionSheet = false
    @State private var selectedEvent: ScheduledEvent?
    
    var body: some View {
        List {
            let startOfToday = Calendar.current.startOfDay(for: Date())
            let futureEvents = store.allEvents.filter { Calendar.current.startOfDay(for: $0.startDate) >= startOfToday }
            let groups = Dictionary(grouping: futureEvents, by: { Calendar.current.startOfDay(for: $0.startDate) })
            let sortedKeys = groups.keys.sorted(by: <)
            
            Section {
                NavigationLink(destination: PastSchedulesView(store: store)) {
                    Label("过往日程", systemImage: "clock.arrow.circlepath")
                        .foregroundColor(.secondary)
                }
            }
            
            ForEach(sortedKeys, id: \.self) { dateKey in
                Section(header: Text(dateKey.formatted(.dateTime.year().month().day()))) {
                    ForEach(groups[dateKey] ?? []) { event in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headline)
                                    .strikethrough(isEventIgnoredOrDeleted(event), color: .secondary)
                                    .foregroundColor(isEventIgnoredOrDeleted(event) ? .secondary : .primary)
                                
                                Text("\(event.startDate.formatted(date: .omitted, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            sourceBadge(for: event)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if isEventIgnoredOrDeleted(event) {
                                Button {
                                    restoreEvent(event)
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            } else {
                                Button(role: .destructive) {
                                    deleteOrIgnoreEvent(event)
                                } label: {
                                    Label("删除/忽略", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("所有日程")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func isEventIgnoredOrDeleted(_ event: ScheduledEvent) -> Bool {
        return !store.events.contains(where: { $0.id == event.id })
    }
    
    private func sourceBadge(for event: ScheduledEvent) -> some View {
        let title: String
        let color: Color
        
        switch event.source {
        case .systemCalendar:
            title = "系统日历"
            color = .blue
        case .ics:
            title = "ICS导入"
            color = .orange
        case .ai:
            title = "AI解析"
            color = .purple
        case .notiee:
            title = "Notiee"
            color = .green
        }
        
        return Text(title)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
    
    private func restoreEvent(_ event: ScheduledEvent) {
        if case .systemCalendar(let identifier) = event.source {
            store.restoreCalendarEvent(identifier: identifier)
        }
        // Custom events can't easily be restored right now if they were deleted completely.
        // Wait, deleted custom events are completely removed from customEvents array!
        // So they won't even appear in allEvents!
        // That means only ignored calendar events can be restored.
    }
    
    private func deleteOrIgnoreEvent(_ event: ScheduledEvent) {
        if case .systemCalendar(let identifier) = event.source {
            store.ignoreCalendarEvent(identifier: identifier, date: event.startDate, future: false)
        } else {
            store.deleteEvent(id: event.id)
        }
    }
}
