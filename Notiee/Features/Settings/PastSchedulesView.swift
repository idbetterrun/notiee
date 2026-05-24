import SwiftUI

struct PastSchedulesView: View {
    @ObservedObject var store: NotieeStore
    
    var body: some View {
        List {
            let startOfToday = Calendar.current.startOfDay(for: Date())
            let pastEvents = store.allEvents.filter { Calendar.current.startOfDay(for: $0.startDate) < startOfToday }
            let groups = Dictionary(grouping: pastEvents, by: { Calendar.current.startOfDay(for: $0.startDate) })
            let sortedKeys = groups.keys.sorted(by: >)
            
            if sortedKeys.isEmpty {
                Text("暂无过往日程")
                    .foregroundColor(.secondary)
            } else {
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
        }
        .navigationTitle("过往日程")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func isEventIgnoredOrDeleted(_ event: ScheduledEvent) -> Bool {
        return !store.events.contains(where: { $0.id == event.id })
    }
    
    private func deleteOrIgnoreEvent(_ event: ScheduledEvent) {
        if event.source == .notiee || event.source == .ai || event.source == .ics {
            store.deleteEvent(id: event.id)
        } else if case .systemCalendar(let identifier) = event.source {
            store.ignoreCalendarEvent(identifier: identifier, date: event.startDate, future: false)
        }
    }
    
    private func restoreEvent(_ event: ScheduledEvent) {
        if case .systemCalendar(let identifier) = event.source {
            store.restoreCalendarEvent(identifier: identifier)
        } else {
            // custom event recovery from trash if implemented, currently custom events just delete
            store.addEvent(event)
        }
    }
}
