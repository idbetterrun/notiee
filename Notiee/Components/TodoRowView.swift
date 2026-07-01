import SwiftUI

struct TodoRowView: View {
    let todo: NoteTodo
    let onToggle: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(todo.content)
                .font(.body.weight(.medium))
                .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                .strikethrough(todo.isCompleted)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
