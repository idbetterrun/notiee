import SwiftUI

struct NottiInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSubmit: () -> Void
    let onStop: () -> Void
    let onFocusChange: (Bool) -> Void

    @FocusState private var isFocused: Bool
    private static let defaultBlue = Color(red: 0.361, green: 0.682, blue: 0.980)
    private var accentColor: Color { NotieeColors.themed(Self.defaultBlue) }

    var body: some View {
        HStack(spacing: 0) {
            TextField("向 Notti 提问...", text: $text, axis: .vertical)
                .font(.body)
                .focused($isFocused)
                .onChange(of: isFocused) { _, new in
                    onFocusChange(new)
                }
                .lineLimit(1...4)
                .padding(.leading, 18)
                .padding(.vertical, 11)

            Button {
                isFocused = false
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 8)
            .opacity(isFocused ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)

            let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button(action: { isLoading ? onStop() : onSubmit() }) {
                Group {
                    if isLoading {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(isEmpty && !isLoading ? Color(.systemGray4) : accentColor, in: Circle())
            }
            .disabled(isEmpty && !isLoading)
            .padding(.trailing, 6)
        }
        .glassSurface(in: RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    VStack {
        Spacer()
        NottiInputBar(
            text: .constant(""),
            isLoading: false,
            onSubmit: {},
            onStop: {},
            onFocusChange: { _ in }
        )
    }
}
