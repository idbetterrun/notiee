import SwiftUI

struct SparkInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSubmit: () -> Void
    let onFocusChange: (Bool) -> Void

    @FocusState private var isFocused: Bool
    private static let defaultBlue = Color(red: 0.361, green: 0.682, blue: 0.980)
    private var accentColor: Color { NotieeColors.themed(Self.defaultBlue) }

    var body: some View {
        HStack(spacing: 0) {
            TextField("向 Spark 提问...", text: $text, axis: .vertical)
                .font(.body)
                .focused($isFocused)
                .onChange(of: isFocused) { _, new in
                    onFocusChange(new)
                }
                .lineLimit(1...4)
                .padding(.leading, 18)
                .padding(.vertical, 11)

            Button(action: onSubmit) {
                Group {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.65)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(
                            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color(.systemGray4)
                                : accentColor
                        )
                )
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .padding(.trailing, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(.ultraThinMaterial)
        )
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
        SparkInputBar(
            text: .constant(""),
            isLoading: false,
            onSubmit: {},
            onFocusChange: { _ in }
        )
    }
}
