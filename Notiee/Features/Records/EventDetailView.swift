import SwiftUI

struct EventDetailView: View {
    let event: ScheduledEvent
    @ObservedObject var store: NotieeStore
    
    var body: some View {
        List {
            ForEach(eventRecords) { record in
                NavigationLink {
                    RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
                } label: {
                    RecordListRow(record: record, eventTitle: store.eventTitle(for: record), dateText: store.formattedDateWithWeek(for: record.capturedAt))
                }
            }
        }
        .navigationTitle(event.title)
        .overlay {
            if eventRecords.isEmpty {
                ContentUnavailableView("暂无照片", systemImage: "photo")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if isSystemCalendarEvent {
                        Button(role: .destructive) {
                            ignoreEvent(future: false)
                        } label: {
                            Label("仅忽略此次", systemImage: "eye.slash")
                        }
                        Button(role: .destructive) {
                            ignoreEvent(future: true)
                        } label: {
                            Label("忽略此次及未来所有", systemImage: "eye.slash.fill")
                        }
                    } else {
                        Button(role: .destructive) {
                            deleteEvent(future: false)
                        } label: {
                            Label("仅删除此次", systemImage: "trash")
                        }
                        Button(role: .destructive) {
                            deleteEvent(future: true)
                        } label: {
                            Label("删除此次及未来所有", systemImage: "trash.fill")
                        }
                    }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
    }
    
    @Environment(\.dismiss) private var dismiss
    
    private var isSystemCalendarEvent: Bool {
        if case .systemCalendar = event.source {
            return true
        }
        return false
    }
    
    private func ignoreEvent(future: Bool) {
        if case .systemCalendar(let identifier) = event.source {
            store.ignoreCalendarEvent(identifier: identifier, date: event.startDate, future: future)
            dismiss()
        }
    }
    
    private func deleteEvent(future: Bool) {
        if future {
            // Delete all custom events with the same title from this date onwards
            let eventsToDelete = store.events.filter { $0.title == event.title && $0.startDate >= event.startDate }
            for e in eventsToDelete {
                store.deleteEvent(id: e.id)
            }
        } else {
            store.deleteEvent(id: event.id)
        }
        dismiss()
    }
    
    private var eventRecords: [NoteRecord] {
        store.sortedRecords.filter { $0.eventID == event.id }
    }
}
