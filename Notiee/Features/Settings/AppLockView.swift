import SwiftUI

/// Full-screen lock overlay. Verifies against AppLockManager and, on success,
/// AppLockManager sets isLocked = false, dismissing this overlay.
struct AppLockView: View {
    @ObservedObject var lock: AppLockManager
    @State private var entered = ""
    @State private var showError = false

    private let pinLength = 6

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
                Text("已锁定").font(.title2.bold())
                Text(showError ? "密码错误，请重试" : "输入密码解锁")
                    .font(.subheadline)
                    .foregroundColor(showError ? .red : .secondary)

                dots

                if lock.biometricEnabled && lock.biometryAvailable {
                    Button {
                        Task { _ = await lock.authenticateWithBiometrics() }
                    } label: {
                        Label("使用 \(lock.biometryTypeName)", systemImage: "faceid")
                    }
                }

                Spacer()
                keypad
                    .padding(.bottom, 24)
            }
            .padding()
        }
        .onAppear {
            if lock.biometricEnabled && lock.biometryAvailable {
                Task { _ = await lock.authenticateWithBiometrics() }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 16) {
            ForEach(0..<pinLength, id: \.self) { i in
                Circle()
                    .fill(i < entered.count ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var keypad: some View {
        let keys: [[String]] = [["1","2","3"],["4","5","6"],["7","8","9"],["","0","⌫"]]
        return VStack(spacing: 18) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 28) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 72, height: 72)
        } else {
            Button {
                handleKey(key)
            } label: {
                Text(key)
                    .font(.title.weight(.regular))
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.secondary.opacity(0.12)))
            }
            .foregroundColor(.primary)
        }
    }

    private func handleKey(_ key: String) {
        showError = false
        if key == "⌫" {
            if !entered.isEmpty { entered.removeLast() }
            return
        }
        guard entered.count < pinLength else { return }
        entered.append(key)
        if entered.count == pinLength {
            if lock.unlockWithPasscode(entered) {
                entered = ""
            } else {
                showError = true
                entered = ""
            }
        }
    }
}
