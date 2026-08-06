import SwiftUI

enum NottiSheet: Identifiable {
    case history
    case privacy
    case record(NoteRecord)

    var id: String {
        switch self {
        case .history: return "history"
        case .privacy: return "privacy"
        case .record(let r): return "record-\(r.id.uuidString)"
        }
    }
}

struct NottiView: View {
    @StateObject private var viewModel: NottiViewModel
    let store: NotieeStore
    @State private var activeSheet: NottiSheet?
    @FocusState private var isFocused: Bool
    @State private var showProUpsell = false
    #if !NOTIEE_PLUS
    // Observe the tier so Agent (un)locking re-renders when a cold-launch or
    // purchase refresh resolves the user as Pro.
    @ObservedObject private var entitlement = EntitlementStore.shared
    #endif

    init(store: NotieeStore) {
        self.store = store
        let vm = NottiViewModel(recordManager: store.recordManager, calendarManager: store.calendarManager, folderTagManager: store.folderTagManager)
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NottiBackgroundView(state: viewModel.state, isInputFocused: isFocused, keyboardHeight: 0)
                    .ignoresSafeArea()

                contentView
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        bottomBar
                    }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Text(viewModel.currentTitle)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                        if viewModel.messages.isEmpty {
                            Text("beta")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
                        } else if viewModel.isGeneratingTitle {
                            ProgressView().scaleEffect(0.6)
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        viewModel.newConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .tint(NotieeColors.themed(.blue))

                    Button {
                        activeSheet = .history
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .tint(NotieeColors.themed(.blue))
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .history:
                NavigationStack {
                    NottiHistoryView(onSelect: { saved in
                        viewModel.loadConversation(saved)
                        activeSheet = nil
                    })
                }
            case .privacy:
                NottiPrivacySheet(onAgree: {
                    viewModel.markPrivacyNoticeSeen()
                    activeSheet = nil
                })
                .interactiveDismissDisabled()
            case .record(let record):
                NavigationStack {
                    RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
                }
            }
        }
        .alert(item: $viewModel.pendingDestructiveConfirmation) { request in
            Alert(
                title: Text("确认执行此操作？"),
                message: Text(String(
                    format: String(localized: "Notti 请求执行“%@”。此操作无法撤销。"),
                    request.detail
                )),
                primaryButton: .destructive(Text("确认执行")) {
                    viewModel.resolveDestructiveConfirmation(confirmed: true)
                },
                secondaryButton: .cancel(Text("取消")) {
                    viewModel.resolveDestructiveConfirmation(confirmed: false)
                }
            )
        }
        .onAppear {
            viewModel.recordsProvider = { [weak store] in store?.records ?? [] }
            if !viewModel.hasSeenPrivacyNotice {
                activeSheet = .privacy
            }
            Task { await viewModel.warmUpSemanticIndex() }
        }
    }

    // MARK: - Content (scrolls behind the floating bars)

    @ViewBuilder
    private var contentView: some View {
        if viewModel.messages.isEmpty {
            VStack {
                Spacer()
                greetingView
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            chatScrollView
        }
    }

    // MARK: - Bottom Bar (floats; chat scrolls behind it)

    private var thinkingTitle: String {
        let id = viewModel.lockedThinkingLevelID ?? viewModel.nottiThinkingLevelID
        if let id, let lvl = viewModel.thinkingLevels.first(where: { $0.id == id }) {
            return lvl.displayName
        }
        return String(localized: "思考强度")
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let warning = viewModel.injectionWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .transition(.opacity)
            }

            if viewModel.sessionLimitReached {
                HStack(spacing: 12) {
                    Text("本次对话已达上限（\(NottiTierLimits.maxSessionRounds ?? 0) 轮）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("开启新会话") { viewModel.newConversation() }
                        .font(.caption.weight(.semibold))
                    Button("升级 Pro") { showProUpsell = true }
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }

            HStack(spacing: 8) {
                NottiAgentChip(
                    isOn: $viewModel.isAgentModeEnabled,
                    locked: !NottiTierLimits.isAgentAllowed,
                    onLockedTap: { showProUpsell = true }
                )
                #if !NOTIEE_PLUS
                .paywallSheet(isPresented: $showProUpsell)
                #endif

                #if NOTIEE_PLUS
                if !viewModel.availableModels.isEmpty {
                    NottiModelChip(
                        title: viewModel.effectiveModelName,
                        icon: "cpu",
                        options: viewModel.availableModels.map { (id: $0, label: $0) },
                        selectedID: viewModel.effectiveModelName,
                        onSelect: { viewModel.selectModel($0) }
                    )
                }
                #endif

                if !viewModel.thinkingLevels.isEmpty {
                    if let locked = viewModel.lockedThinkingLevelID {
                        NottiModelChip(
                            title: thinkingTitle,
                            icon: "brain",
                            options: viewModel.thinkingLevels.filter { $0.id == locked }.map { (id: $0.id, label: $0.displayName) },
                            selectedID: locked,
                            onSelect: { _ in }
                        )
                        .disabled(true)
                        .opacity(0.6)
                    } else {
                        NottiModelChip(
                            title: thinkingTitle,
                            icon: "brain",
                            options: viewModel.thinkingLevels.map { (id: $0.id, label: $0.displayName) },
                            selectedID: viewModel.nottiThinkingLevelID,
                            onSelect: { viewModel.selectThinkingLevel($0) }
                        )
                    }
                }

                Spacer()
            }
            .padding(.leading, 48)
            .padding(.trailing, 24)
            .padding(.bottom, 2)

            NottiInputBar(
                text: $viewModel.inputText,
                isLoading: viewModel.state == .loading,
                onSubmit: { viewModel.sendOrRun() },
                onStop: { viewModel.cancelResponse() },
                onFocusChange: { _ in }
            )
            .padding(.horizontal, 16)

            Text("内容由AI生成，\(AppBranding.appName)不会把拍记内容用于任何模型训练")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
        .background {
            // 内容向底部渐隐成磨砂，保证免责声明/输入区可读，同时上方仍通透
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        colors: [.clear, .black, .black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Greeting

    private var greetingView: some View {
        VStack(spacing: 24) {
            Text(viewModel.greetingEmoji)
                .font(.system(size: 56))

            Text(viewModel.greetingText)
                .font(.title2.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if !viewModel.currentQuestions.isEmpty {
                VStack(spacing: 10) {
                    ForEach(viewModel.currentQuestions, id: \.self) { question in
                        Button {
                            viewModel.sendQuestion(question)
                        } label: {
                            Text(question)
                                .font(.subheadline)
                                .foregroundStyle(NotieeColors.themed(.blue))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(NotieeColors.themed(.blue).opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Chat Scroll

    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        NottiChatBubble(
                            message: message,
                            store: store,
                            onCitationTap: { recordID in
                                if let record = store.records.first(where: { $0.id == recordID }) {
                                    activeSheet = .record(record)
                                }
                            }
                        )
                        .id(message.id)

                        if viewModel.agentSuggestionMessageID == message.id {
                            HStack {
                                Button {
                                    viewModel.acceptAgentSuggestion()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "bolt.fill")
                                        Text("用 Agent 模式重试")
                                    }
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .glassSurface(in: RoundedRectangle(cornerRadius: 14))
                                    .foregroundStyle(Color.purple)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .transition(.opacity)
                        }
                    }

                    if viewModel.state == .loading && (viewModel.currentToolName != nil || !viewModel.agentActions.isEmpty) {
                        NottiAgentTimelineView(
                            actions: viewModel.agentActions,
                            runningToolName: viewModel.currentToolName
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        NottiView(store: NotieeStore.sample())
    }
}
