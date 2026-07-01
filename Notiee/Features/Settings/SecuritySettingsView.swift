import SwiftUI

struct SecuritySettingsView: View {
    @ObservedObject var store: NotieeStore
    @StateObject private var lock = AppLockManager.shared

    @State private var showSetPasscode = false
    @State private var showVerifyDisable = false
    @State private var showDisableConfirm = false
    @State private var recordToDecrypt: NoteRecord?
    @State private var errorText: String?

    private var encryptedRecords: [NoteRecord] {
        store.records.filter { $0.isEncrypted && !$0.isDeleted }
    }

    var body: some View {
        Form {
            appLockSection

            if lock.isEnabled {
                biometricSection
                deleteProtectionSection
                encryptedRecordsSection
            }

            if let errorText {
                Section { Text(errorText).foregroundColor(.red) }
            }
        }
        .navigationTitle("安全")
        .navigationBarTitleDisplayMode(.inline)
        // Set passcode (enable flow)
        .sheet(isPresented: $showSetPasscode) {
            SetPasscodeSheet(
                biometryTypeName: lock.biometryTypeName,
                biometryAvailable: lock.biometryAvailable,
                onCancel: { showSetPasscode = false }
            ) { code, useBiometric in
                lock.enable(passcode: code, biometric: lock.biometryAvailable && useBiometric)
                showSetPasscode = false
                if lock.biometricEnabled {
                    Task { await lock.primeBiometricPermission() }
                }
            }
        }
        // Verify identity to disable security
        .sheet(isPresented: $showVerifyDisable) {
            PasscodeUnlockView(
                lock: lock,
                title: "验证以关闭",
                subtitle: "验证身份后即可关闭安全功能",
                reason: "关闭安全功能",
                onAuthenticated: {
                    showVerifyDisable = false
                    if encryptedRecords.isEmpty {
                        lock.disable()
                    } else {
                        showDisableConfirm = true
                    }
                },
                onCancel: { showVerifyDisable = false }
            )
        }
        // Verify identity to decrypt one record
        .sheet(item: $recordToDecrypt) { record in
            PasscodeUnlockView(
                lock: lock,
                title: "验证以解除加密",
                subtitle: "验证身份后解除该拍记的加密",
                reason: "解除拍记加密",
                onAuthenticated: {
                    store.decryptRecord(id: record.id)
                    recordToDecrypt = nil
                },
                onCancel: { recordToDecrypt = nil }
            )
        }
        .alert("确认关闭安全功能？", isPresented: $showDisableConfirm) {
            Button("取消", role: .cancel) {}
            Button("解密全部并关闭", role: .destructive) {
                store.decryptAllRecords()
                lock.disable()
            }
        } message: {
            Text("将解密 \(encryptedRecords.count) 条已加密拍记并恢复为明文。")
        }
    }

    // MARK: - Sections

    private var appLockSection: some View {
        Section {
            Toggle("打开 App 需要密码", isOn: Binding(
                get: { lock.isEnabled },
                set: { newValue in
                    errorText = nil
                    if newValue {
                        showSetPasscode = true
                    } else {
                        showVerifyDisable = true
                    }
                }
            ))
        } footer: {
            Text("开启后每次启动或从后台返回都需要验证身份。")
        }
    }

    private var biometricSection: some View {
        Section {
            Toggle("使用 \(lock.biometryTypeName) 快速解锁", isOn: Binding(
                get: { lock.biometricEnabled },
                set: { newValue in
                    UserDefaults.standard.set(newValue, forKey: UDK.securityBiometricEnabled)
                    // Trigger the OS permission prompt immediately instead of at first unlock.
                    if newValue {
                        Task { await lock.primeBiometricPermission() }
                    }
                }
            ))
            .disabled(!lock.biometryAvailable)
        } footer: {
            Text(lock.biometryAvailable
                 ? "解锁 App 与查看/管理加密拍记时可用。"
                 : "此设备不支持生物识别。")
        }
    }

    private var deleteProtectionSection: some View {
        Section {
            Toggle("删除加密拍记需验证身份", isOn: Binding(
                get: { lock.requiresAuthForEncryptedDelete },
                set: { lock.setRequiresAuthForEncryptedDelete($0) }
            ))
        } footer: {
            Text("开启后，删除任意已加密拍记前都需要通过密码或 \(lock.biometryTypeName) 验证，防止误删或被他人删除。")
        }
    }

    private var encryptedRecordsSection: some View {
        Section {
            if encryptedRecords.isEmpty {
                Text("暂无加密拍记。在记录详情页「更多 → 加密该条拍记」加密。")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(encryptedRecords) { record in
                    HStack(spacing: 12) {
                        Image(systemName: "lock.doc.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已加密拍记")
                                .font(.subheadline.weight(.medium))
                            Text(record.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("解除加密") { recordToDecrypt = record }
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        } header: {
            Text("已加密的拍记")
        } footer: {
            Text("关闭单条拍记的加密只能在此处操作，且需验证身份。")
        }
    }
}

// MARK: - Set passcode sheet (keypad, two-step)

/// Two-step passcode creation using the shared keypad: enter, then confirm.
private struct SetPasscodeSheet: View {
    let biometryTypeName: String
    let biometryAvailable: Bool
    let onCancel: () -> Void
    /// (passcode, enableBiometric)
    let onDone: (String, Bool) -> Void

    private let pinLength = 6

    @State private var first = ""
    @State private var entered = ""
    @State private var stage: Stage = .create
    @State private var showError = false
    @State private var shakeTrigger = 0
    @State private var useBiometric = true
    @Environment(\.colorScheme) private var colorScheme

    private enum Stage { case create, confirm }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: onCancel)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private var content: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                Image(systemName: stage == .create ? "lock.rotation" : "lock.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .modifier(AccentGlassCircle())

                Text(stage == .create ? "设置 6 位密码" : "再次输入确认")
                    .font(.title2.weight(.bold))
                    .padding(.top, 22)

                Text(showError ? "两次输入不一致，请重新设置" : "用于打开 App 及保护加密拍记")
                    .font(.subheadline)
                    .foregroundStyle(showError ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)

                PasscodeDotsView(filled: entered.count, total: pinLength, isError: showError)
                    .padding(.top, 28)
                    .modifier(PasscodeShakeEffect(animatableData: CGFloat(shakeTrigger)))

                Spacer(minLength: 24)

                if biometryAvailable {
                    Toggle(isOn: $useBiometric) {
                        Label("同时开启 \(biometryTypeName) 快速解锁", systemImage: "faceid")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                }

                PasscodeKeypad(onDigit: append, onDelete: deleteLast)
                    .padding(.bottom, 28)
            }
        }
    }

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

    private func append(_ digit: String) {
        guard entered.count < pinLength else { return }
        showError = false
        entered.append(digit)
        Haptics.tap()
        if entered.count == pinLength { advance() }
    }

    private func deleteLast() {
        guard !entered.isEmpty else { return }
        showError = false
        entered.removeLast()
    }

    private func advance() {
        switch stage {
        case .create:
            first = entered
            entered = ""
            stage = .confirm
            Haptics.tap()
        case .confirm:
            if entered == first {
                Haptics.success()
                onDone(entered, useBiometric)
            } else {
                Haptics.error()
                withAnimation(.default) { shakeTrigger += 1 }
                showError = true
                entered = ""
                first = ""
                stage = .create
            }
        }
    }
}
