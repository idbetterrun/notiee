import SwiftUI

// MARK: - Markdown Parser

private enum MarkdownLine: Equatable {
    case heading1(String)
    case heading2(String)
    case heading3(String)
    case blockquote(String)
    case bullet(String)
    case numbered(Int, String)
    case code(String)
    case plain(String)
    case empty
}

private struct MarkdownParser {
    static func parse(_ text: String) -> [MarkdownLine] {
        var lines: [MarkdownLine] = []
        var inCodeBlock = false
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock { lines.append(.code(raw)); continue }
            if line.isEmpty { lines.append(.empty); continue }
            if line.hasPrefix("### ") || line.hasPrefix("###") {
                let t = line.hasPrefix("### ") ? String(line.dropFirst(4)) : String(line.dropFirst(3))
                lines.append(.heading3(t.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("## ") || line.hasPrefix("##") {
                let t = line.hasPrefix("## ") ? String(line.dropFirst(3)) : String(line.dropFirst(2))
                lines.append(.heading2(t.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("# ") || line.hasPrefix("#") {
                let t = line.hasPrefix("# ") ? String(line.dropFirst(2)) : String(line.dropFirst(1))
                lines.append(.heading1(t.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("> ") || line.hasPrefix(">") {
                let t = line.hasPrefix("> ") ? String(line.dropFirst(2)) : String(line.dropFirst(1))
                lines.append(.blockquote(t.trimmingCharacters(in: .whitespaces)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("-") || line.hasPrefix("*") {
                let drop = line.hasPrefix("- ") || line.hasPrefix("* ") ? 2 : 1
                lines.append(.bullet(String(line.dropFirst(drop)).trimmingCharacters(in: .whitespaces)))
            } else if let match = try? NSRegularExpression(pattern: "^(\\d+)\\. ").firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let r = Range(match.range(at: 1), in: line),
                      let num = Int(line[r]) {
                let content = String(line[Range(match.range, in: line)!.upperBound...]).trimmingCharacters(in: .whitespaces)
                lines.append(.numbered(num, content))
            } else {
                lines.append(.plain(raw))
            }
        }
        return lines
    }
}

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
                renderedMarkdown
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16).padding(.vertical, 8)

                if !message.citations.isEmpty {
                    citationsSection
                }
            }
        }
    }

    // MARK: - Rendered Markdown

    private var renderedMarkdown: some View {
        let lines = MarkdownParser.parse(message.content)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                renderLine(line, isFirst: idx == 0, isLast: idx == lines.count - 1)
            }
        }
    }

    @ViewBuilder
    private func renderLine(_ line: MarkdownLine, isFirst: Bool, isLast: Bool) -> some View {
        switch line {
        case .heading1(let t):
            renderInlines(t)
                .font(.title2.weight(.bold))
                .padding(.top, isFirst ? 0 : 12)
                .padding(.bottom, 2)
        case .heading2(let t):
            renderInlines(t)
                .font(.title3.weight(.semibold))
                .padding(.top, isFirst ? 0 : 10)
                .padding(.bottom, 2)
        case .heading3(let t):
            renderInlines(t)
                .font(.headline)
                .padding(.top, isFirst ? 0 : 8)
                .padding(.bottom, 1)
        case .blockquote(let t):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                renderInlines(t)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
            }
            .padding(.vertical, 2)
        case .bullet(let t):
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .padding(.top, 8)
                renderInlines(t)
                    .font(.body)
            }
            .padding(.leading, 6)
        case .numbered(let n, let t):
            HStack(alignment: .top, spacing: 4) {
                Text("\(n).")
                    .font(.body)
                    .foregroundStyle(.secondary)
                renderInlines(t)
                    .font(.body)
            }
            .padding(.leading, 6)
        case .code(let t):
            Text(t)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemGray5)))
                .padding(.vertical, 2)
        case .plain(let t):
            renderInlines(t)
                .font(.body)
                .padding(.vertical, 1)
        case .empty:
            Color.clear.frame(height: 8)
        }
    }

    // MARK: - Inline Formatter (bold, italic, code, link)

    private func renderInlines(_ text: String) -> Text {
        var result = Text("")
        var remaining = text
        while !remaining.isEmpty {
            if let match = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*").firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
               let fullR = Range(match.range, in: remaining),
               let innerR = Range(match.range(at: 1), in: remaining) {
                if fullR.lowerBound > remaining.startIndex {
                    result = result + Text(String(remaining[remaining.startIndex..<fullR.lowerBound]))
                }
                result = result + Text(String(remaining[innerR])).bold()
                remaining = String(remaining[fullR.upperBound...])
            } else if let match = try? NSRegularExpression(pattern: "\\*(.+?)\\*").firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
                      let fullR = Range(match.range, in: remaining),
                      let innerR = Range(match.range(at: 1), in: remaining) {
                if fullR.lowerBound > remaining.startIndex {
                    result = result + Text(String(remaining[remaining.startIndex..<fullR.lowerBound]))
                }
                result = result + Text(String(remaining[innerR])).italic()
                remaining = String(remaining[fullR.upperBound...])
            } else if let match = try? NSRegularExpression(pattern: "`(.+?)`").firstMatch(in: remaining, range: NSRange(remaining.startIndex..., in: remaining)),
                      let fullR = Range(match.range, in: remaining),
                      let innerR = Range(match.range(at: 1), in: remaining) {
                if fullR.lowerBound > remaining.startIndex {
                    result = result + Text(String(remaining[remaining.startIndex..<fullR.lowerBound]))
                }
                result = result + Text(String(remaining[innerR]))
                    .font(.callout.monospaced())
                    .foregroundStyle(Color(red: 0.361, green: 0.682, blue: 0.980))
                remaining = String(remaining[fullR.upperBound...])
            } else {
                result = result + Text(remaining)
                remaining = ""
            }
        }
        return result
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

