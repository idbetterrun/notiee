import SwiftUI

struct EventImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var events: [ScheduledEvent]
    let store: NotieeStore
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("解析到的日程 (\(events.count)个)"), footer: Text("点击任意一条可修改其信息。确认无误后点击右上角导入。")) {
                    ForEach($events) { $event in
                        NavigationLink {
                            EventEditView(event: $event, store: store)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.title)
                                    .font(.headline)
                                Text("\(event.startDate.formatted(date: .abbreviated, time: .shortened)) - \(event.endDate.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("日程预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认导入") {
                        for event in events {
                            store.addEvent(event)
                        }
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
    }
}

fileprivate struct EventEditView: View {
    @Binding var event: ScheduledEvent
    let store: NotieeStore
    
    var body: some View {
        Form {
            Section("详细信息") {
                TextField("标题", text: $event.title)
                DatePicker("开始时间", selection: $event.startDate)
                DatePicker("结束时间", selection: $event.endDate)
            }
            
            Section("标签与备注") {
                Picker("标签", selection: $event.tagID) {
                    Text("无标签").tag(nil as UUID?)
                    ForEach(store.customTags) { tag in
                        Text(tag.name).tag(tag.id as UUID?)
                    }
                }
                
                TextField("备注", text: Binding(
                    get: { event.notes ?? "" },
                    set: { event.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
            }
        }
        .navigationTitle("编辑日程")
        .navigationBarTitleDisplayMode(.inline)
    }
}
