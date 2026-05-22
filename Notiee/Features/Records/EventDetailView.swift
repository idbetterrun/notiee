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
                    RecordListRow(record: record, eventTitle: store.eventTitle(for: record))
                }
            }
        }
        .navigationTitle(event.title)
        .overlay {
            if eventRecords.isEmpty {
                ContentUnavailableView("暂无照片", systemImage: "photo")
            }
        }
    }
    
    private var eventRecords: [NoteRecord] {
        store.sortedRecords.filter { $0.eventID == event.id }
    }
}
