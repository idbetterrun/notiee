import SwiftUI

struct RecordEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NoteRecord
    @State private var draftTodos: [NoteTodo]
    let onSave: (NoteRecord, [NoteTodo]) -> Void
    
    init(record: NoteRecord, todos: [NoteTodo], onSave: @escaping (NoteRecord, [NoteTodo]) -> Void) {
        self._draft = State(initialValue: record)
        self._draftTodos = State(initialValue: todos)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("标题") {
                    TextField("记录标题", text: $draft.title)
                }
                
                Section("AI 摘要") {
                    TextEditor(text: $draft.summary)
                        .frame(minHeight: 80)
                }
                
                Section("详细内容") {
                    TextEditor(text: $draft.detailedContent)
                        .frame(minHeight: 120)
                }
                
                Section("待办事项") {
                    ForEach($draftTodos) { $todo in
                        TextField("待办内容", text: $todo.content)
                    }
                    .onDelete { indices in
                        draftTodos.remove(atOffsets: indices)
                    }
                    Button("添加待办") {
                        draftTodos.append(NoteTodo(recordID: draft.id, content: ""))
                    }
                }
                
                Section("OCR 原文") {
                    TextEditor(text: $draft.ocrText)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        draft.editedAt = Date()
                        onSave(draft, draftTodos)
                        dismiss()
                    }
                }
            }
        }
    }
}
