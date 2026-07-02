import SwiftUI

// MARK: - App-lock overlay

/// Full-screen lock overlay shown while `AppLockManager.isLocked` is true.
struct AppLockView: View {
    @ObservedObject var lock: AppLockManager

    var body: some View {
        PasscodeUnlockView(
            lock: lock,
            title: "已锁定",
            subtitle: "输入密码解锁 \(AppBranding.appName)",
            reason: "解锁 \(AppBranding.appName)",
            autoPromptBiometric: true,
            onAuthenticated: { lock.isLocked = false }
        )
    }
}

// MARK: - Reusable unlock / verify screen

/// A polished passcode + biometric gate. Powers both the app-lock overlay and any
/// "verify to continue" sheet (viewing / deleting / decrypting a record, disabling
/// security). Biometric success and passcode success both call `onAuthenticated`;
/// neither mutates `AppLockManager.isLocked` directly (the caller decides).
struct PasscodeUnlockView: View {
    @ObservedObject var lock: AppLockManager
    let title: String
    var subtitle: String = "输入密码继续"
    var reason: String = "验证身份"
    /// Auto-run biometric on appear (used by the full-screen overlay).
    var autoPromptBiometric: Bool = false
    let onAuthenticated: () -> Void
    /// When provided a Cancel affordance is shown (sheet presentation).
    var onCancel: (() -> Void)? = nil

    private let pinLength = 6

    @State private var entered = ""
    @State private var showError = false
    @State private var shakeTrigger = 0
    @State private var biometricInFlight = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let onCancel {
            // Sheet presentation: a standard, correctly-sized nav-bar Cancel button.
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消", action: onCancel)
                        }
                    }
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer(minLength: 12)

                lockGlyph
                    .padding(.bottom, 22)

                Text(title)
                    .font(.title2.weight(.bold))

                Text(showError ? "密码错误，请重试" : subtitle)
                    .font(.subheadline)
                    .foregroundStyle(showError ? Color.red : Color.secondary)
                    .padding(.top, 6)
                    .animation(.easeInOut(duration: 0.2), value: showError)

                PasscodeDotsView(filled: entered.count, total: pinLength, isError: showError)
                    .padding(.top, 28)
                    .modifier(PasscodeShakeEffect(animatableData: CGFloat(shakeTrigger)))

                Spacer(minLength: 24)

                PasscodeKeypad(
                    showsBiometric: canUseBiometric,
                    biometricSymbol: biometricSymbol,
                    onDigit: append,
                    onDelete: deleteLast,
                    onBiometric: { Task { await runBiometric() } }
                )
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            if autoPromptBiometric && canUseBiometric {
                Task { await runBiometric() }
            }
        }
    }

    // MARK: Pieces

    private var background: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(white: 0.06), Color.black]
                : [Color(.systemGroupedBackground), Color(.secondarySystemGroupedBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var lockGlyph: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 38, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .modifier(AccentGlassCircle())
    }

    private var canUseBiometric: Bool { lock.biometricEnabled && lock.biometryAvailable }

    private var biometricSymbol: String {
        lock.biometryTypeName == "Touch ID" ? "touchid" : "faceid"
    }

    // MARK: Input handling

    private func append(_ digit: String) {
        guard entered.count < pinLength else { return }
        showError = false
        entered.append(digit)
        Haptics.tap()
        if entered.count == pinLength { submit() }
    }

    private func deleteLast() {
        guard !entered.isEmpty else { return }
        showError = false
        entered.removeLast()
    }

    private func submit() {
        if lock.verifyPasscode(entered) {
            entered = ""
            Haptics.success()
            onAuthenticated()
        } else {
            fail()
        }
    }

    private func fail() {
        entered = ""
        showError = true
        Haptics.error()
        withAnimation(.default) { shakeTrigger += 1 }
    }

    private func runBiometric() async {
        guard canUseBiometric, !biometricInFlight else { return }
        biometricInFlight = true
        defer { biometricInFlight = false }
        if await lock.authenticateWithBiometrics(reason: reason) {
            Haptics.success()
            onAuthenticated()
        }
    }
}

// MARK: - Dots

struct PasscodeDotsView: View {
    let filled: Int
    let total: Int
    var isError: Bool = false

    var body: some View {
        HStack(spacing: 20) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(fill(for: i))
                    .frame(width: 13, height: 13)
                    .overlay(
                        Circle().strokeBorder(Color.secondary.opacity(0.35), lineWidth: i < filled ? 0 : 1)
                    )
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: filled)
            }
        }
    }

    private func fill(for index: Int) -> Color {
        guard index < filled else { return .clear }
        return isError ? .red : .accentColor
    }
}

// MARK: - Keypad

struct PasscodeKeypad: View {
    var showsBiometric: Bool = false
    var biometricSymbol: String = "faceid"
    let onDigit: (String) -> Void
    let onDelete: () -> Void
    var onBiometric: (() -> Void)? = nil

    private let columns = Array(repeating: GridItem(.fixed(78), spacing: 26), count: 3)

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 22) { grid }
        } else {
            grid
        }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(1...9, id: \.self) { n in
                digitKey("\(n)")
            }
            biometricOrEmptyKey
            digitKey("0")
            deleteKey
        }
    }

    private func digitKey(_ value: String) -> some View {
        Button { onDigit(value) } label: {
            Text(value)
                .font(.system(size: 32, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 78, height: 78)
                .modifier(GlassKeyBackground())
        }
        .buttonStyle(KeyPressStyle())
    }

    @ViewBuilder
    private var biometricOrEmptyKey: some View {
        if showsBiometric, let onBiometric {
            Button(action: onBiometric) {
                Image(systemName: biometricSymbol)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 78, height: 78)
                    .contentShape(Circle())
            }
            .buttonStyle(KeyPressStyle())
        } else {
            Color.clear.frame(width: 78, height: 78)
        }
    }

    private var deleteKey: some View {
        Button(action: onDelete) {
            Image(systemName: "delete.left")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 78, height: 78)
                .contentShape(Circle())
        }
        .buttonStyle(KeyPressStyle())
    }
}

/// Liquid-Glass circular key background on iOS 26+, with a soft translucent
/// fallback for iOS 18–25.
private struct GlassKeyBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
    }
}

/// Accent-tinted circular badge for the lock glyph — Liquid Glass on iOS 26+,
/// tinted circle fallback below. Shared by the lock screen and passcode setup.
struct AccentGlassCircle: ViewModifier {
    var diameter: CGFloat = 96
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .frame(width: diameter, height: diameter)
                .glassEffect(.regular.tint(Color.accentColor.opacity(0.28)), in: .circle)
        } else {
            content
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12)))
        }
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Shake effect

struct PasscodeShakeEffect: GeometryEffect {
    var amount: CGFloat = 9
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * CGFloat(shakesPerUnit))
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

#Preview("Lock") {
    AppLockView(lock: AppLockManager.shared)
}
