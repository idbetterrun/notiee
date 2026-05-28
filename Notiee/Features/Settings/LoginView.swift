import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasAgreed = false
    @State private var isLoggingIn = false
    @State private var showTimeoutAlert = false
    @State private var showAgreementReminder = false
    @State private var appear = false
    @State private var shakeCount = 0
    @State private var reminderBounces = false

    private let timeoutSeconds: UInt64 = 3

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            if isDark {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.06, blue: 0.05), Color(red: 0.04, green: 0.03, blue: 0.03)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Spacer()

                heroSection
                    .padding(.bottom, 56)
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 24)

                Spacer()

                VStack(spacing: 20) {
                    agreementSection

                    primaryLoginButton
                        .modifier(ShakeEffect(animatableData: CGFloat(shakeCount)))

                    if showAgreementReminder {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                            Text("请先同意用户协议和隐私政策")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                        .scaleEffect(reminderBounces ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.5), value: reminderBounces)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 36)
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 16)

                Spacer().frame(height: 44)
            }

            if isLoggingIn {
                loginOverlay
            }
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: appear)
        .animation(.easeInOut(duration: 0.25), value: isLoggingIn)
        .navigationTitle("登录")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .alert("连接超时", isPresented: $showTimeoutAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("无法连接到 TomaGo 服务，请稍后重试。")
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) {
                appear = true
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(NotieeColors.primary.opacity(0.1))
                    .frame(width: 120, height: 120)

                NotieeLogoMark(size: 76, cornerRadius: 20)
            }

            VStack(spacing: 10) {
                Text("Notiee")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundColor(isDark ? .white : .primary)

                Text("每一张板书，都可搜索的知识流")
                    .font(.subheadline)
                    .foregroundColor(isDark ? .white.opacity(0.45) : .secondary)
                    .tracking(0.5)
            }
        }
    }

    // MARK: - Primary Button

    private var primaryLoginButton: some View {
        Button {
            attemptLogin()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.fill.checkmark")
                    .font(.system(size: 14, weight: .semibold))
                Text("通过 TomaGo 登录")
                    .font(.body.weight(.semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(NotieeColors.primary)
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.15), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .shadow(color: NotieeColors.primary.opacity(0.3), radius: 12, y: 4)
        }
        .scaleEffect(isLoggingIn ? 0.97 : 1)
        .animation(.easeInOut(duration: 0.2), value: isLoggingIn)
    }

    // MARK: - Agreement

    private var agreementSection: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    hasAgreed.toggle()
                }
                if hasAgreed {
                    showAgreementReminder = false
                    reminderBounces = false
                }
            } label: {
                Image(systemName: hasAgreed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(hasAgreed ? NotieeColors.primary : (isDark ? .white.opacity(0.2) : .secondary.opacity(0.5)))
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Text("登录即表示同意 ")
                    .font(.caption)
                    .foregroundColor(isDark ? .white.opacity(0.3) : .secondary.opacity(0.7))
                NavigationLink {
                    legalPDFViewForLogin(base: "UserAgreement", title: "用户协议")
                } label: {
                    Text("《用户协议》")
                        .font(.caption.weight(.medium))
                        .foregroundColor(NotieeColors.primary)
                }
                Text(" 和 ")
                    .font(.caption)
                    .foregroundColor(isDark ? .white.opacity(0.3) : .secondary.opacity(0.7))
                NavigationLink {
                    legalPDFViewForLogin(base: "PrivacyPolicy", title: "隐私政策")
                } label: {
                    Text("《隐私政策》")
                        .font(.caption.weight(.medium))
                        .foregroundColor(NotieeColors.primary)
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Login Overlay

    private var loginOverlay: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .transition(.opacity)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.1), lineWidth: 3)
                        .frame(width: 64, height: 64)

                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(NotieeColors.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(isLoggingIn ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isLoggingIn)
                }

                VStack(spacing: 4) {
                    Text("正在连接 TomaGo")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.9))
                    Text("请稍候…")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .frame(width: 180, height: 180)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func attemptLogin() {
        guard hasAgreed else {
            withAnimation(.linear(duration: 0)) {
                shakeCount += 1
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                reminderBounces = true
                showAgreementReminder = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                reminderBounces = false
            }
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

// MARK: - Shake Effect

private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let amplitude: CGFloat = 10
        let shakes = 3
        let decay: CGFloat = 0.8
        let t = animatableData
        let fraction = t - floor(t)
        let factor = pow(decay, CGFloat(Int(t)))
        let offset: CGFloat
        if fraction < 0.5 / CGFloat(shakes) {
            offset = amplitude * sin(CGFloat(shakes) * fraction * 2 * .pi) * factor
        } else {
            offset = 0
        }
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
