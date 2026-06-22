import SwiftUI
import MarkdownUI

// MARK: - Chat Bubble

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
        .task {
            if message.content.isEmpty && message.role == .assistant {
                thinkingPhase = 1.0
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
            .contextMenu {
                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
            }
    }

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.content.isEmpty {
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 6, height: 6)
                            .scaleEffect(thinkingPhase > 0 ? (0.6 + 0.6 * sin(thinkingPhase * .pi * 2 + Double(i) * 0.8)) : 1.0)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: thinkingPhase)
            } else {
                Markdown(message.content)
                    .markdownTheme(.spark)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                    }

                if !message.citations.isEmpty {
                    citationsSection
                }
            }
        }
    }

    // MARK: - Citations

    private var citationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
                .padding(.top, 4)
            Text("参考来源")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            ForEach(message.citations) { citation in
                SparkCitationRow(citation: citation, store: store, onTap: { recordID in
                    onCitationTap?(recordID)
                })
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Spark Markdown Theme

private extension MarkdownUI.Theme {
    static let spark = MarkdownUI.Theme()
        .text {
            FontSize(17)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(15)
            ForegroundColor(Color(red: 0.361, green: 0.682, blue: 0.980))
        }
        .strong {
            FontWeight(.bold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: .rem(0.75), bottom: .rem(0.125))
                .markdownTextStyle {
                    FontSize(22)
                    FontWeight(.bold)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: .rem(0.625), bottom: .rem(0.125))
                .markdownTextStyle {
                    FontSize(20)
                    FontWeight(.semibold)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: .rem(0.5), bottom: .rem(0.0625))
                .markdownTextStyle {
                    FontSize(17)
                    FontWeight(.semibold)
                }
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle {
                        FontStyle(.italic)
                        ForegroundColor(.secondary)
                    }
                    .padding(.leading, 10)
            }
        }
        .table { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .markdownTableBorderStyle(
                        TableBorderStyle(
                            .insideHorizontalBorders,
                            color: Color.secondary.opacity(0.2),
                            width: 0.5
                        )
                    )
                    .markdownTableBackgroundStyle(
                        TableBackgroundStyle { row, _ in
                            row == 0 ? Color.secondary.opacity(0.08) : Color.clear
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    FontSize(15)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
        }
}

#Preview {
    VStack(spacing: 16) {
        SparkChatBubble(
            message: ChatMessage(role: .assistant, content: """
            # 标题一
            这是正文内容，支持 **粗体** 和 *斜体* 以及 `行内代码`。

            ## 标题二
            > 这是一段引用文字，用来展示引用块的样式。

            ### 列表示例
            - 第一项
            - 第二项，包含 **粗体文字**
            - 第三项

            1. 有序列表第一项
            2. 有序列表第二项

            | 功能 | 说明 |
            |------|------|
            | 搜索 | 关键词检索 |

            | Mon | Tue | Wed | Thu | Fri | Sat | Sun |
            |-----|-----|-----|-----|-----|-----|-----|
            | A | B | C | D | E | F | G |

            ---
            正文继续。
            """),
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
