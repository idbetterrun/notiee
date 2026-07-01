import SwiftUI

struct SecuritySettingsView: View {
    @ObservedObject var store: NotieeStore
    @StateObject private var lock = AppLockManager.shared

    @State private var showSetPasscode = false
    @State private var showDisableConfirm = false
    @State private var pendingPasscode = ""
    @State private var confirmPasscode = ""
    @State private var enableBiometric = true
    @State private var verifyInput = ""
    @State private var showVerifyForDisable = false
    @State private var errorText: String?

    private var encryptedRecords: [NoteRecord] {
        store.records.filter { $0.isEncrypted && !$0.isDeleted }
    }

    var body: some View {
        Form {
            Section {
                Toggle("打开 App 需要密码", isOn: Binding(
                    get: { lock.isEnabled },
                    set: { newValue in
                        if newValue {
                            showSetPasscode = true
                        } else {
                            showVerifyForDisable = true
                        }
                    }
                ))
            } footer: {
                Text("开启后每次启动或从后台返回都需要验证。")
            }

            if lock.isEnabled {
                Section {
                    Toggle("使用 \(lock.biometryTypeName) 快速解锁", isOn: Binding(
                        get: { lock.biometricEnabled },
                        set: { UserDefaults.standard.set($0, forKey: UDK.securityBiometricEnabled) }
                    ))
                    .disabled(!lock.biometryAvailable)
                } footer: {
                    Text(lock.biometryAvailable ? "解锁 App 与查看加密拍记时可用。" : "此设备不支持生物识别。")
                }

                Section {  // "已加密的拍记"
                    if encryptedRecords.isEmpty {
                        Text("暂无加密拍记。在记录详情页「更多 → 加密该条拍记」加密。")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(encryptedRecords) { record in
                            HStack {
                                Image(systemName: "lock.doc.fill").foregroundColor(.accentColor)
                                Text(record.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                                Button("解除加密") {
                                    authenticate { store.decryptRecord(id: record.id) }
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                } header: {
                    Text("已加密的拍记")
                } footer: {
                    Text("关闭单条拍记的加密只能在此处操作。")
                }
            }

            if let errorText {
                Section { Text(errorText).foregroundColor(.red) }
            }
        }
        .navigationTitle("安全")
        .navigationBarTitleDisplayMode(.inline)
        // Set passcode flow
        .sheet(isPresented: $showSetPasscode) {
            SetPasscodeSheet(onCancel: { showSetPasscode = false }) { code in
                lock.enable(passcode: code, biometric: lock.biometryAvailable && enableBiometric)
                showSetPasscode = false
            }
        }
        // Verify to disable
        .alert("验证以关闭安全", isPresented: $showVerifyForDisable) {
            SecureField("6 位密码", text: $verifyInput)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) { verifyInput = "" }
            Button("确认关闭", role: .destructive) {
                if lock.verifyPasscode(verifyInput) {
                    verifyInput = ""
                    if !encryptedRecords.isEmpty {
                        showDisableConfirm = true
                    } else {
                        lock.disable()
                    }
                } else {
                    errorText = "密码错误。"
                    verifyInput = ""
                }
            }
        } message: {
            Text("关闭后所有已加密拍记将被解密恢复为明文。")
        }
        .alert("确认关闭安全功能？", isPresented: $showDisableConfirm) {
            Button("取消", role: .cancel) {}
            Button("解密全部并关闭", role: .destructive) {
                store.decryptAllRecords()
                lock.disable()
            }
        } message: {
            Text("将解密 \(encryptedRecords.count) 条已加密拍记。")
        }
        .alert("输入密码", isPresented: $showActionPrompt) {
            SecureField("6 位密码", text: $actionPasscode).keyboardType(.numberPad)
            Button("取消", role: .cancel) { actionPasscode = ""; pendingAction = nil }
            Button("确认") {
                if lock.verifyPasscode(actionPasscode), let act = pendingAction {
                    act()
                } else {
                    errorText = "密码错误。"
                }
                actionPasscode = ""
                pendingAction = nil
            }
        }
    }

    /// Runs `action` after a fresh biometric/passcode check.
    private func authenticate(_ action: @escaping () -> Void) {
        Task {
            if await lock.authenticateWithBiometrics(reason: "解除拍记加密") {
                action()
            } else {
                // Fallback: require passcode via a simple prompt.
                await MainActor.run { showPasscodePromptForAction(action) }
            }
        }
    }

    // Minimal inline passcode prompt fallback for per-record decrypt.
    @State private var actionPasscode = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showActionPrompt = false

    private func showPasscodePromptForAction(_ action: @escaping () -> Void) {
        pendingAction = action
        showActionPrompt = true
    }
}

/// Two-field passcode creation sheet.
private struct SetPasscodeSheet: View {
    let onCancel: () -> Void
    let onDone: (String) -> Void
    @State private var a = ""
    @State private var b = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {  // "设置 6 位密码"
                    SecureField("输入密码", text: $a).keyboardType(.numberPad)
                    SecureField("再次输入", text: $b).keyboardType(.numberPad)
                } header: {
                    Text("设置 6 位密码")
                }
                if let error { Text(error).foregroundColor(.red) }
            }
            .navigationTitle("设置密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        guard a.count == 6, a.allSatisfy(\.isNumber) else { error = "请输入 6 位数字。"; return }
                        guard a == b else { error = "两次输入不一致。"; return }
                        onDone(a)
                    }
                }
            }
        }
    }
}
