import SwiftUI

struct SwipeableTodoRow: View {
    let todo: NoteTodo
    let onToggleComplete: () -> Void
    let onDelete: () -> Void
    
    @State private var offset: CGFloat = 0
    @State private var isSwiping = false
    
    var body: some View {
        ZStack {
            // Background for swipe actions
            HStack {
                // Left-to-right background (Complete/Uncomplete)
                if offset > 0 {
                    Rectangle()
                        .fill(todo.isCompleted ? .orange : .green)
                        .overlay(alignment: .leading) {
                            Image(systemName: todo.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                .foregroundStyle(.white)
                                .font(.title3.weight(.semibold))
                                .padding(.leading, 20)
                        }
                }
                
                Spacer()
                
                // Right-to-left background (Delete)
                if offset < 0 {
                    Rectangle()
                        .fill(.red)
                        .overlay(alignment: .trailing) {
                            Image(systemName: "trash")
                                .foregroundStyle(.white)
                                .font(.title3.weight(.semibold))
                                .padding(.trailing, 20)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Foreground row
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        onToggleComplete()
                    }
                } label: {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(todo.isCompleted ? .green : .secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)

                Text(todo.content)
                    .font(.body.weight(.medium))
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .strikethrough(todo.isCompleted)

                Spacer()
            }
            .padding(14)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .offset(x: offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isSwiping = true
                        let width = value.translation.width
                        // Add some resistance
                        offset = width > 0 ? pow(width, 0.8) : -pow(-width, 0.8)
                    }
                    .onEnded { value in
                        isSwiping = false
                        let width = value.translation.width
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if width > 80 {
                                // Trigger Complete
                                onToggleComplete()
                                offset = 0
                            } else if width < -80 {
                                // Trigger Delete
                                onDelete()
                                offset = 0
                            } else {
                                offset = 0
                            }
                        }
                    }
            )
        }
    }
}
