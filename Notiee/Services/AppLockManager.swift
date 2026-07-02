import Foundation
import LocalAuthentication
import Combine

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published var isLocked: Bool = false

    private let secretStore: SecretPersisting
    private var backgroundedAt: Date?
    /// True while a system biometric sheet is being presented. The biometric prompt
    /// briefly resigns/backgrounds the app; without this guard the scene lifecycle
    /// would record a background timestamp and re-lock the instant we unlock,
    /// producing an unlock↔lock loop.
    private var isAuthenticating = false

    private static let passcodeHashKey = "notiee.security.passcodeHash"
    private static let passcodeSaltKey = "notiee.security.passcodeSalt"

    init(secretStore: SecretPersisting = KeychainSecretStore()) {
        self.secretStore = secretStore
        // Lock on cold start if the feature is enabled.
        isLocked = isEnabled
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UDK.securityAppLockEnabled)
    }

    var biometricEnabled: Bool {
        UserDefaults.standard.bool(forKey: UDK.securityBiometricEnabled)
    }

    var hasPasscode: Bool {
        secretStore.string(forKey: Self.passcodeHashKey) != nil
    }

    /// Whether deleting an encrypted record must be confirmed with passcode/biometric.
    /// Defaults to `true` when the user has never toggled it.
    var requiresAuthForEncryptedDelete: Bool {
        UserDefaults.standard.object(forKey: UDK.securityRequireEncryptedDeleteAuth) as? Bool ?? true
    }

    func setRequiresAuthForEncryptedDelete(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: UDK.securityRequireEncryptedDeleteAuth)
        objectWillChange.send()
    }

    /// True if the given record's deletion should be gated behind identity verification.
    func shouldAuthForDeleting(_ record: NoteRecord) -> Bool {
        isEnabled && record.isEncrypted && requiresAuthForEncryptedDelete
    }

    private var graceSeconds: TimeInterval {
        let v = UserDefaults.standard.integer(forKey: UDK.securityAutoLockGraceSeconds)
        return v > 0 ? TimeInterval(v) : 0 // 0 = lock immediately on return
    }

    // MARK: - Passcode

    func setPasscode(_ passcode: String) {
        let salt = CryptoService.makeSalt()
        let hash = CryptoService.hashPasscode(passcode, salt: salt)
        try? secretStore.setString(salt, forKey: Self.passcodeSaltKey)
        try? secretStore.setString(hash, forKey: Self.passcodeHashKey)
    }

    func verifyPasscode(_ passcode: String) -> Bool {
        guard let salt = secretStore.string(forKey: Self.passcodeSaltKey),
              let hash = secretStore.string(forKey: Self.passcodeHashKey) else { return false }
        return CryptoService.verifyPasscode(passcode, salt: salt, expectedHash: hash)
    }

    func clearPasscode() {
        try? secretStore.removeString(forKey: Self.passcodeHashKey)
        try? secretStore.removeString(forKey: Self.passcodeSaltKey)
    }

    // MARK: - Enable / disable

    func enable(passcode: String, biometric: Bool) {
        setPasscode(passcode)
        UserDefaults.standard.set(true, forKey: UDK.securityAppLockEnabled)
        UserDefaults.standard.set(biometric, forKey: UDK.securityBiometricEnabled)
        isLocked = false
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: UDK.securityAppLockEnabled)
        UserDefaults.standard.set(false, forKey: UDK.securityBiometricEnabled)
        clearPasscode()
        isLocked = false
    }

    // MARK: - Locking lifecycle

    func appDidEnterBackground() {
        guard isEnabled else { return }
        // Ignore the transient background caused by the biometric prompt itself.
        guard !isAuthenticating else { return }
        backgroundedAt = Date()
    }

    func appWillEnterForeground() {
        guard isEnabled else { return }
        // Only re-lock if we actually went to the background. Cold start is handled by
        // `init`; spurious `.active` transitions (e.g. after dismissing the Face ID
        // sheet) must NOT re-lock, or the lock screen loops forever.
        guard let at = backgroundedAt else { return }
        backgroundedAt = nil
        if Date().timeIntervalSince(at) < graceSeconds { return }
        isLocked = true
    }

    func lockNow() {
        guard isEnabled else { return }
        isLocked = true
    }

    // MARK: - Biometric

    var biometryTypeName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "生物识别"
        }
    }

    var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Authenticate with biometrics. Returns whether it succeeded; does NOT mutate
    /// `isLocked` — callers decide what a success unlocks (the app, a record, a delete…).
    /// Returns `false` (letting the UI fall back to passcode) if biometrics are
    /// disabled or unavailable.
    func authenticateWithBiometrics(reason: String = "解锁 \(AppBranding.appName)") async -> Bool {
        let ctx = LAContext()
        guard biometricEnabled, ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return false
        }
        isAuthenticating = true
        defer { isAuthenticating = false }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
        } catch {
            return false
        }
    }

    /// Triggers the OS biometric-permission prompt immediately (used the moment the
    /// user enables "quick unlock", so the permission dialog isn't deferred until the
    /// first real unlock).
    func primeBiometricPermission() async {
        let ctx = LAContext()
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        _ = try? await ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "开启 \(biometryTypeName) 快速解锁"
        )
    }

    func unlockWithPasscode(_ passcode: String) -> Bool {
        guard verifyPasscode(passcode) else { return false }
        isLocked = false
        return true
    }
}
