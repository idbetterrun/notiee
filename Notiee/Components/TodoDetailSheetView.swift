import SwiftUI

struct TodoDetailSheetView: View {
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
