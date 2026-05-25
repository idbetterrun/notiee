import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hasAgreed = false
    @State private var isLoggingIn = false
    @State private var showTimeoutAlert = false
    @State private var showAgreementReminder = false

    private let timeoutSeconds: UInt64 = 3

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        NotieeLogoMark(size: 88, cornerRadius: 20)

                        Text("Notiee")
                            .font(.system(size: 32, weight: .bold, design: .rounded))

                        Text("登录后即可启用多端同步与云端备份，\n随时随地访问你的拍记。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 60)

                    VStack(spacing: 16) {
                        Button {
                            attemptLogin()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "person.fill.checkmark")
                                    .font(.system(size: 16))
                                Text("通过 TomaGo 登录")
                                    .font(.body.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                        }

                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 1)
                            Text("或")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(height: 1)
                        }

                        HStack(spacing: 20) {
                            thirdPartyButton(label: "微信", color: .green) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.green)
                                        .frame(width: 32, height: 32)
                                    Text("微")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            thirdPartyButton(label: "Apple", color: .black) {
                                Image(systemName: "apple.logo")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8))
                            }
                            thirdPartyButton(label: "Google", color: .red) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white)
                                        .frame(width: 32, height: 32)
                                        .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                                    Text("G")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)

                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    hasAgreed.toggle()
                                }
                                if hasAgreed { showAgreementReminder = false }
                            } label: {
                                Image(systemName: hasAgreed ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 20))
                                    .foregroundColor(hasAgreed ? .blue : .secondary)
                            }

                            HStack(spacing: 0) {
                                Text("登录即表示同意")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                NavigationLink {
                                    legalPDFViewForLogin(base: "UserAgreement", title: "用户协议")
                                } label: {
                                    Text("《用户协议》")
                                        .font(.caption)
                                }
                                Text("和")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                NavigationLink {
                                    legalPDFViewForLogin(base: "PrivacyPolicy", title: "隐私政策")
                                } label: {
                                    Text("《隐私政策》")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.horizontal, 4)

                        if showAgreementReminder {
                            Text("请先同意用户协议和隐私政策")
                                .font(.caption2)
                                .foregroundColor(.red)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 32)

                    Text("你的数据始终属于你，Notiee 不会窥探你的隐私。")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                }
            }
            .scrollBounceBehavior(.basedOnSize)

            if isLoggingIn {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("正在连接...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .frame(width: 160, height: 120)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoggingIn)
        .animation(.easeInOut(duration: 0.15), value: showAgreementReminder)
        .navigationTitle("登录")
        .navigationBarTitleDisplayMode(.inline)
        .alert("连接超时", isPresented: $showTimeoutAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("无法连接到 TomaGo 服务，请稍后重试。")
        }
    }

    private func thirdPartyButton(label: String, color: Color, @ViewBuilder icon: () -> some View) -> some View {
        Button {
            attemptLogin()
        } label: {
            VStack(spacing: 6) {
                icon()
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func attemptLogin() {
        guard hasAgreed else {
            withAnimation { showAgreementReminder = true }
            return
        }
        isLoggingIn = true
        Task {
            try? await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
            await MainActor.run {
                isLoggingIn = false
                showTimeoutAlert = true
            }
        }
    }

    private func legalPDFViewForLogin(base: String, title: String) -> some View {
        Group {
            if let url = Bundle.main.url(forResource: "\(base)_zh-Hans", withExtension: "pdf") {
                PDFPreviewView(url: url)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                Text("无法加载\(title)")
                    .padding()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
