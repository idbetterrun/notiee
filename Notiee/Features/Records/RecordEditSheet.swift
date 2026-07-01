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

                Section("知识点") {
                    ForEach(Array(draft.keyPoints.enumerated()), id: \.offset) { idx, point in
                        HStack {
                            TextField("知识点", text: Binding(
                                get: { point },
                                set: { draft.keyPoints[idx] = $0 }
                            ))
                            Button {
                                draft.keyPoints.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    Button {
                        draft.keyPoints.append("")
                    } label: {
                        Label("添加知识点", systemImage: "plus.circle")
                    }
                }

                Section("名词解释") {
                    ForEach(Array(draft.definitions.enumerated()), id: \.offset) { idx, def in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("术语", text: Binding(
                                get: { def.term },
                                set: { draft.definitions[idx].term = $0 }
                            ))
                            .font(.body.weight(.semibold))
                            TextField("解释", text: Binding(
                                get: { def.explanation },
                                set: { draft.definitions[idx].explanation = $0 }
                            ))
                            .font(.subheadline)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                draft.definitions.remove(at: idx)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        draft.definitions.append(KeyDefinition(term: "", explanation: ""))
                    } label: {
                        Label("添加名词解释", systemImage: "plus.circle")
                    }
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
