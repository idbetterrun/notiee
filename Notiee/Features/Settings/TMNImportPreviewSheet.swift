import SwiftUI

struct TMNImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let record: NoteRecord
    let todos: [NoteTodo]
    let store: NotieeStore
    
    var body: some View {
        NavigationStack {
            List {
                Section("导入详情") {
                    LabeledContent("标题", value: record.title)
                    LabeledContent("摘要", value: record.summary.isEmpty ? "无摘要" : record.summary)
                    LabeledContent("照片数量", value: "\(record.localImagePaths.count) 张")
                    LabeledContent("待办事项", value: "\(todos.count) 条")
                }
                
                if !record.detailedContent.isEmpty {
                    Section("详细内容") {
                        Text(record.detailedContent)
                            .font(.body)
                    }
                }
            }
            .navigationTitle("导入预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        for todo in todos {
                            store.addTodo(todo)
                        }
                        var importedRecord = record
                        importedRecord.folderID = store.createImportedFolder()
                        store.addRecord(importedRecord)
                        dismiss()
                    }
                    .font(.headline)
                }
            }
        }
    }
}
