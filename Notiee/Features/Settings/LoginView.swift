import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var account = AccountStore.live
    @State private var hasAgreed = false
    @State private var showAgreementReminder = false
    @State private var appear = false
    @State private var shakeCount = 0
    @State private var reminderBounces = false
    @State private var loginErrorMessage: String?
    #if !NOTIEE_PLUS
    // Free version: one-shot nonce for the current Sign in with Apple attempt.
    @State private var loginNonce: LoginNonce?
    #endif

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

                    NavigationLink {
                        LocalLoginView()
                    } label: {
                        Text("本地登录")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(NotieeColors.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }

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

        }
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: appear)
        .navigationTitle("登录")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false)
        .alert("登录失败", isPresented: Binding(get: { loginErrorMessage != nil }, set: { if !$0 { loginErrorMessage = nil } })) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(loginErrorMessage ?? "")
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.1)) {
                appear = true
            }
        }
        // 本地登录成功后，LocalLoginView 先 dismiss 自身回到本页，本页再 dismiss 自身，
        // 两级 push 依次弹出，最终回到「我」页面。两处各自 dismiss 自身，是 NavigationStack 的标准用法。
        .onChange(of: account.isLoggedIn) { _, loggedIn in
            if loggedIn { dismiss() }
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
                Text(AppBranding.appName)
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
        // Apple's official button (auto-localized label + correct Apple mark),
        // which is the compliant way to present Sign in with Apple.
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName]
            #if !NOTIEE_PLUS
            // Free version: request email (backend needs it on first login) and
            // bind a nonce so the identity token can't be replayed at the backend.
            request.requestedScopes = [.fullName, .email]
            let nonce = AuthService.shared.makeLoginNonce()
            loginNonce = nonce
            request.nonce = nonce.hashed
            #endif
        } onCompletion: { result in
            handleAppleResult(result)
        }
        .signInWithAppleButtonStyle(isDark ? .white : .black)
        .frame(height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            // Until the user accepts the terms, intercept taps and nudge them to
            // the agreement instead of opening the system sheet.
            if !hasAgreed {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.001))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                    .onTapGesture { promptAgreement() }
            }
        }
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
                    legalHTMLViewForLogin(base: "UserAgreement", title: "用户协议")
                } label: {
                    Text("《用户协议》")
                        .font(.caption.weight(.medium))
                        .foregroundColor(NotieeColors.primary)
                }
                Text(" 和 ")
                    .font(.caption)
                    .foregroundColor(isDark ? .white.opacity(0.3) : .secondary.opacity(0.7))
                NavigationLink {
                    legalHTMLViewForLogin(base: "PrivacyPolicy", title: "隐私政策")
                } label: {
                    Text("《隐私政策》")
                        .font(.caption.weight(.medium))
                        .foregroundColor(NotieeColors.primary)
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Actions

    /// Shake + nudge the user toward the agreement checkbox when they try to sign
    /// in before accepting the terms.
    private func promptAgreement() {
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
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                loginErrorMessage = String(localized: "无法完成 Apple 登录，请稍后重试。")
                return
            }
            // fullName is only provided on the first authorization for this Apple ID.
            let name = credential.fullName.flatMap { components -> String? in
                let formatted = PersonNameComponentsFormatter().string(from: components)
                return formatted.isEmpty ? nil : formatted
            }
            #if NOTIEE_PLUS
            account.appleLogin(userID: credential.user, name: name)
            // account.isLoggedIn flips to true → onChange dismisses this view.
            #else
            // Free version: exchange the identity token for a backend session
            // before marking the user logged in.
            handleBackendAppleLogin(credential: credential, name: name)
            #endif
        case .failure(let error):
            // Silently ignore a user-initiated cancel.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            loginErrorMessage = String(localized: "无法完成 Apple 登录，请稍后重试。")
        }
    }

    #if !NOTIEE_PLUS
    /// Free version: exchange the Apple identity token for a backend JWT, then
    /// associate the local profile with the backend account. Runs in the
    /// authorization callback while the identity token is still fresh.
    private func handleBackendAppleLogin(credential: ASAuthorizationAppleIDCredential, name: String?) {
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            loginErrorMessage = String(localized: "无法完成 Apple 登录，请稍后重试。")
            return
        }
        let rawNonce = loginNonce?.raw
        let userID = credential.user
        Task { @MainActor in
            do {
                let session = try await AuthService.shared.appleLogin(identityToken: identityToken, rawNonce: rawNonce, name: name)
                // Prefer the backend's stored name: on a reinstall Apple no longer
                // hands us `fullName`, but the backend still has the first-login one.
                account.appleLogin(userID: userID, name: session.name ?? name, backendUserID: session.userId, email: session.email)
                // account.isLoggedIn flips to true → onChange dismisses this view.
            } catch {
                loginErrorMessage = String(localized: "登录失败，请检查网络后重试。")
            }
        }
    }
    #endif

    private func legalHTMLViewForLogin(base: String, title: String) -> some View {
        Group {
            if let url = LegalDocument.bundleURL(base: base) {
                LegalHTMLView(url: url)
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
