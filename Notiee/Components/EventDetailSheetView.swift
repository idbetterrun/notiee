import SwiftUI

struct EventDetailSheetView: View {
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
