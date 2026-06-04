import SwiftUI

struct SparkView: View {
    @StateObject private var viewModel: SparkViewModel
    let store: NotieeStore
    @State private var showHistory = false
    @State private var showPrivacy = false
    @State private var selectedRecord: NoteRecord?
    @FocusState private var isFocused: Bool

    init(store: NotieeStore) {
        self.store = store
        let vm = SparkViewModel()
        vm.recordsProvider = { [weak store] in store?.records ?? [] }
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        ZStack {
            SparkBackgroundView(state: viewModel.state, isInputFocused: isFocused, keyboardHeight: 0)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                    .padding(.top, 8)

                if viewModel.messages.isEmpty {
                    Spacer()
                    greetingView
                    Spacer()
                } else {
                    chatScrollView
                }

                if let warning = viewModel.injectionWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .transition(.opacity)
                }

                if let memText = viewModel.memoryActionText {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                        Text(memText)
                            .font(.caption)
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                SparkInputBar(
                    text: $viewModel.inputText,
                    isLoading: viewModel.state == .loading,
                    onSubmit: { viewModel.sendMessage() },
                    onFocusChange: { _ in }
                )
                .padding(.horizontal, 16)

                Text("内容由AI生成，Notiee不会把拍记内容用于任何模型训练")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showHistory) {
            NavigationStack {
                SparkHistoryView(onSelect: { saved in viewModel.loadConversation(saved); showHistory = false })
            }
        }
        .sheet(isPresented: $showPrivacy) {
            SparkPrivacySheet(onAgree: { viewModel.markPrivacyNoticeSeen(); showPrivacy = false })
        }
        .sheet(item: $selectedRecord) { record in
            NavigationStack {
                RecordDetailView(viewModel: RecordDetailViewModel(record: record, store: store))
            }
        }
        .onAppear {
            if !viewModel.hasSeenPrivacyNotice {
                showPrivacy = true
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(viewModel.currentTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                if viewModel.messages.isEmpty {
                    Text("beta")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.15))
                        )
                } else if viewModel.isGeneratingTitle {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }

            Spacer()

            Button {
                viewModel.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NotieeColors.themed(.blue))
            }

            Button {
                showHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NotieeColors.themed(.blue))
            }
            .padding(.leading, 16)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
                        SparkChatBubble(
                            message: message,
                            store: store,
                            onCitationTap: { recordID in
                                if let record = store.records.first(where: { $0.id == recordID }) {
                                    selectedRecord = record
                                }
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SparkView(store: NotieeStore.sample())
    }
}
