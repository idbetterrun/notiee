import MarkdownUI
import SwiftUI
import UIKit

struct NewUIPreviewComposerView: View {
    @EnvironmentObject private var previewState: NewUIPreviewState
    @EnvironmentObject private var chat: NewUIPreviewNottiState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isInputFocused: Bool

    @State private var showingHistory = false
    @State private var isNearBottom = true
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    private let bottomAnchor = "new-ui-preview-notti-bottom"

    var body: some View {
        ZStack {
            Color.newUIPreviewBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                conversation
                composer
            }

            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .newUIPreviewGlass(in: Capsule())
                    .padding(.top, 70)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showingHistory) {
            NewUIPreviewNottiHistoryView {
                isNearBottom = true
                isInputFocused = true
            }
                .environmentObject(chat)
        }
        .task {
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }
            isInputFocused = true
        }
        .onDisappear {
            toastTask?.cancel()
            chat.stopGenerating()
        }
        .accessibilityIdentifier("new-ui-preview-notti")
    }

    private var topBar: some View {
        ZStack {
            Text(verbatim: "Notti")
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 132)

            HStack(spacing: 10) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .newUIPreviewGlass(in: Circle(), interactive: true)
                }
                .buttonStyle(NewUIPreviewPressStyle())
                .accessibilityLabel("关闭 Notti")

                Spacer(minLength: 0)

                NewUIPreviewGlassContainer {
                    HStack(spacing: 0) {
                        Button {
                            beginNewConversation()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("新对话")

                        Button { showingHistory = true } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("对话历史")
                    }
                    .newUIPreviewGlass(in: Capsule(), interactive: true)
                }
            }
        }
        .foregroundStyle(Color.newUIPreviewPrimary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .frame(height: 60)
    }

    @ViewBuilder
    private var conversation: some View {
        if chat.messages.isEmpty {
            emptyState
        } else {
            chatScrollView
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 24)
            ForEach(Array(chat.promptShortcuts.enumerated()), id: \.offset) { index, prompt in
                Button {
                    chat.submit(prompt: shortcutPrompt(at: index), reduceMotion: reduceMotion)
                } label: {
                    Label(prompt, systemImage: shortcutSymbol(at: index))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.newUIPreviewPrimary)
                        .padding(.horizontal, 15)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                        .newUIPreviewGlass(in: Capsule(), interactive: true)
                }
                .buttonStyle(NewUIPreviewPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(chat.messages) { message in
                        messageView(message)
                            .id(message.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let visibleBottom = geometry.contentOffset.y
                    + geometry.contentInsets.top
                    + geometry.containerSize.height
                let contentBottom = geometry.contentSize.height + geometry.contentInsets.bottom
                return visibleBottom >= contentBottom - 96
            } action: { _, newValue in
                guard isNearBottom != newValue else { return }
                DispatchQueue.main.async {
                    isNearBottom = newValue
                }
            }
            .onChange(of: chat.messages.isEmpty) { _, isEmpty in
                if isEmpty { isNearBottom = true }
            }
            .onChange(of: chat.messages.count) { _, _ in
                guard isNearBottom else { return }
                scrollToBottom(proxy, animated: !reduceMotion)
            }
            .onChange(of: chat.messages.last?.content) { _, _ in
                guard isNearBottom else { return }
                scrollToBottom(proxy, animated: false)
            }
            .overlay(alignment: .bottom) {
                if !isNearBottom {
                    Button {
                        scrollToBottom(proxy, animated: !reduceMotion, force: true)
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .newUIPreviewGlass(in: Circle(), interactive: true)
                    }
                    .buttonStyle(NewUIPreviewPressStyle())
                    .accessibilityLabel("回到最新回答")
                    .padding(.bottom, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func messageView(_ message: NewUIPreviewNottiMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        NotieeColors.themed(Color(red: 0.361, green: 0.682, blue: 0.980)),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if message.content.isEmpty {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Notti 正在整理")
                            .font(.subheadline)
                            .foregroundStyle(Color.newUIPreviewSecondary)
                    }
                    .frame(minHeight: 32)
                } else {
                    Markdown(message.content)
                        .markdownTheme(.newUIPreviewNotti)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !message.isComplete {
                        NewUIPreviewStreamingCursor(animate: !reduceMotion)
                    }
                }

                if message.isComplete, message.id == chat.messages.last(where: { $0.role == .assistant })?.id {
                    HStack(spacing: 8) {
                        Button {
                            UIPasteboard.general.string = message.content
                            showToast(String(localized: "已复制"))
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .accessibilityLabel("复制")
                        .help("复制")

                        Button {
                            chat.regenerate(reduceMotion: reduceMotion)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 40, height: 40)
                                .contentShape(Circle())
                        }
                        .accessibilityLabel("重新生成")
                        .help("重新生成")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.newUIPreviewSecondary)
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chat.webSearchEnabled || chat.agentModeEnabled {
                HStack(spacing: 8) {
                    if chat.webSearchEnabled {
                        activeModeChip("联网搜索", symbol: "globe") {
                            chat.webSearchEnabled = false
                        }
                    }
                    if chat.agentModeEnabled {
                        activeModeChip("Agent", symbol: "bolt.fill") {
                            chat.agentModeEnabled = false
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            VStack(spacing: 6) {
                TextField("问问 Notti…", text: $chat.inputText, axis: .vertical)
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .font(.system(size: 17))
                    .submitLabel(.send)
                    .onSubmit {
                        guard !chat.inputText.contains("\n") else { return }
                        chat.submit(reduceMotion: reduceMotion)
                    }

                HStack(spacing: 8) {
                    plusMenu
                    thinkingMenu
                    Spacer(minLength: 0)
                    sendButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 13)
            .padding(.bottom, 10)
            .newUIPreviewGlass(
                in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                interactive: true
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var plusMenu: some View {
        Menu {
            Menu {
                ForEach(chat.modelOptions) { model in
                    Button {
                        chat.selectModel(model.id)
                    } label: {
                        if model.id == chat.selectedModelID {
                            Label(model.title, systemImage: "checkmark")
                        } else {
                            Text(model.title)
                        }
                    }
                }
            } label: {
                Label(chat.selectedModelTitle, systemImage: "cpu")
            }

            Button {
                chat.webSearchEnabled.toggle()
            } label: {
                Label("联网搜索", systemImage: chat.webSearchEnabled ? "checkmark" : "globe")
            }

            Button {
                chat.agentModeEnabled.toggle()
            } label: {
                Label("Agent 模式", systemImage: chat.agentModeEnabled ? "checkmark" : "bolt")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .accessibilityLabel("更多输入选项")
    }

    private var thinkingMenu: some View {
        Menu {
            ForEach(NewUIPreviewNottiThinking.allCases) { option in
                Button {
                    chat.selectedThinking = option
                } label: {
                    if option == chat.selectedThinking {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(chat.selectedThinking.title)
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("思考强度：\(chat.selectedThinking.title)")
    }

    private var sendButton: some View {
        Button {
            if chat.isGenerating {
                chat.stopGenerating()
            } else {
                chat.submit(reduceMotion: reduceMotion)
            }
        } label: {
            Image(systemName: chat.isGenerating ? "stop.fill" : "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(sendButtonColor, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(NewUIPreviewPressStyle())
        .disabled(!chat.isGenerating && chat.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(chat.isGenerating ? "停止生成" : "发送")
    }

    private var sendButtonColor: Color {
        if chat.isGenerating || !chat.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .newUIPreviewAccent
        }
        return Color(uiColor: .systemGray3)
    }

    private func activeModeChip(_ title: LocalizedStringKey, symbol: String, onRemove: @escaping () -> Void) -> some View {
        Button(action: onRemove) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .frame(minHeight: 34)
                .foregroundStyle(Color.newUIPreviewAccent)
                .background(Color.newUIPreviewAccent.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func close() {
        isInputFocused = false
        chat.stopGenerating()
        previewState.collapse()
    }

    private func beginNewConversation() {
        chat.newConversation()
        isNearBottom = true
        isInputFocused = true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool, force: Bool = false) {
        guard force || isNearBottom else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
        if force { isNearBottom = true }
    }

    private func shortcutSymbol(at index: Int) -> String {
        ["sparkles", "clock.arrow.circlepath", "bolt.fill"][index]
    }

    private func shortcutPrompt(at index: Int) -> String {
        [
            String(localized: "分析一下我最近记录中的重点"),
            String(localized: "帮我复盘最近的产品记录"),
            String(localized: "整理一下本周还没完成的事情")
        ][index]
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        toastTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return
            }
            withAnimation(.easeIn(duration: 0.18)) { toast = nil }
            toastTask = nil
        }
    }
}

private extension MarkdownUI.Theme {
    @MainActor
    static let newUIPreviewNotti = MarkdownUI.Theme()
        .text {
            FontSize(16)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(14)
            ForegroundColor(Color.newUIPreviewAccent)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: .rem(0.7), bottom: .rem(0.1))
                .markdownTextStyle {
                    FontSize(21)
                    FontWeight(.bold)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: .rem(0.6), bottom: .rem(0.1))
                .markdownTextStyle {
                    FontSize(19)
                    FontWeight(.semibold)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: .rem(0.5), bottom: .rem(0.05))
                .markdownTextStyle {
                    FontSize(17)
                    FontWeight(.semibold)
                }
        }
}

private struct NewUIPreviewStreamingCursor: View {
    let animate: Bool

    @State private var opacity = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.newUIPreviewAccent)
            .frame(width: 3, height: 18)
            .opacity(opacity)
            .onAppear {
                guard animate else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    opacity = 0.25
                }
            }
            .transition(.opacity)
    }
}

private struct NewUIPreviewNottiHistoryView: View {
    @EnvironmentObject private var chat: NewUIPreviewNottiState
    @Environment(\.dismiss) private var dismiss

    let onSelect: () -> Void

    var body: some View {
        NavigationStack {
            List(chat.savedConversations) { conversation in
                Button {
                    chat.loadConversation(conversation)
                    onSelect()
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(conversation.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(conversation.messages.last?.content ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("对话历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
