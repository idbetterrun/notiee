import SwiftUI

struct AllTodosView: View {
    @ObservedObject var store: NotieeStore
    @State private var selectedTodo: NoteTodo?
    @State private var showCreate = false
    @State private var completedCollapsed = true

    private var pending: [NoteTodo] {
        store.todos.filter { !$0.isCompleted }
    }
    private var completed: [NoteTodo] {
        store.todos.filter { $0.isCompleted }.sorted { $0.createdAt > $1.createdAt }
    }

    private func grouped() -> [(bucket: TodoDueBucket, items: [NoteTodo])] {
        let groups = Dictionary(grouping: pending) { TodoBucketer.bucket(for: $0) }
        return TodoDueBucket.allCases.compactMap { bucket in
            guard let items = groups[bucket], !items.isEmpty else { return nil }
            let sorted = items.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            return (bucket, sorted)
        }
    }

    var body: some View {
        List {
            ForEach(grouped(), id: \.bucket.rawValue) { group in
                Section(group.bucket.title) {
                    ForEach(group.items) { todo in row(todo) }
                }
            }

            if !completed.isEmpty {
                Section {
                    if !completedCollapsed {
                        ForEach(completed) { todo in row(todo) }
                    }
                } header: {
                    Button {
                        withAnimation { completedCollapsed.toggle() }
                    } label: {
                        HStack {
                            Text("已完成 (\(completed.count))")
                            Spacer()
                            Image(systemName: completedCollapsed ? "chevron.right" : "chevron.down")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("所有待办")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $selectedTodo) { todo in
            TodoDetailSheetView(todo: todo, viewModel: TodayViewModel(store: store))
        }
        .sheet(isPresented: $showCreate) {
            CreateItemSheet(viewModel: TodayViewModel(store: store))
        }
    }

    private func row(_ todo: NoteTodo) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { store.toggleTodo(id: todo.id) }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.content)
                    .strikethrough(todo.isCompleted, color: .secondary)
                    .foregroundColor(todo.isCompleted ? .secondary : .primary)
                HStack(spacing: 8) {
                    if let due = todo.dueDate {
                        Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if todo.hasReminder {
                        Image(systemName: "bell.fill").font(.caption2).foregroundColor(.orange)
                    }
                    if let rid = todo.recordID,
                       let rec = store.records.first(where: { $0.id == rid }) {
                        Label(rec.title, systemImage: "doc.text")
                            .font(.caption2).foregroundColor(.blue).lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedTodo = todo }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.deleteTodo(id: todo.id) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
