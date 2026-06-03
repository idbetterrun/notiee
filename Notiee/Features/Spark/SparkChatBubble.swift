import SwiftUI

struct SparkChatBubble: View {
    let message: ChatMessage
    let store: NotieeStore
    let onCitationTap: ((UUID) -> Void)?

    @State private var thinkingPhase: Double = 0

    private static let defaultBlue = Color(red: 0.361, green: 0.682, blue: 0.980)
    private var accentColor: Color { NotieeColors.themed(Self.defaultBlue) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .assistant {
                assistantContent
                Spacer(minLength: 48)
            } else {
                Spacer(minLength: 48)
                userContent
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
        }
        .onAppear {
            if message.content.isEmpty && message.role == .assistant {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    thinkingPhase = 1.0
                }
            }
        }
    }

    private var userContent: some View {
        Text(message.content)
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(accentColor)
            )
    }

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.content.isEmpty {
                // Thinking animation — bouncing dots
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .scaleEffect(thinkingPhase > 0 ? (0.6 + 0.6 * sin(thinkingPhase * .pi * 2 + Double(i) * 0.8)) : 1.0)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                // Plain text on background — no bubble styling for assistant
                sparkMarkdownContent(message.content)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineSpacing(4)
                    .padding(.horizontal, 16).padding(.vertical, 8)

                if !message.citations.isEmpty {
                    citationsSection
                }
            }
        }
    }

    // Spark always renders markdown, independent of lab toggle
    private func sparkMarkdownContent(_ text: String) -> some View {
        if let attr = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return AnyView(Text(attr))
        }
        return AnyView(Text(text))
    }

    private var citationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.top, 4)
            Text("参考来源")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ForEach(message.citations) { citation in
                SparkCitationRow(citation: citation, store: store)
            }
        }
        .padding(.horizontal, 12)
    }
}

#Preview {
    VStack(spacing: 16) {
        SparkChatBubble(
            message: ChatMessage(role: .assistant, content: "你好！我是 Spark，有什么可以帮助你的？"),
            store: NotieeStore.sample(),
            onCitationTap: { _ in }
        )
        SparkChatBubble(
            message: ChatMessage(role: .user, content: "帮我回顾一下最近的笔记"),
            store: NotieeStore.sample(),
            onCitationTap: { _ in }
        )
    }
    .padding()
}
