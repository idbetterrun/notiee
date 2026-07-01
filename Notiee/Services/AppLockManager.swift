import Foundation
import LocalAuthentication
import Combine

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published var isLocked: Bool = false

    private let secretStore: SecretPersisting
    private var backgroundedAt: Date?

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
        backgroundedAt = Date()
    }

    func appWillEnterForeground() {
        guard isEnabled else { return }
        if let at = backgroundedAt, Date().timeIntervalSince(at) < graceSeconds {
            return
        }
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

    /// Authenticate with biometrics; on success clears the lock. Completion(false) lets the
    /// UI fall back to passcode entry.
    func authenticateWithBiometrics(reason: String = "解锁 Notiee") async -> Bool {
        let ctx = LAContext()
        guard biometricEnabled, ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return false
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if ok { isLocked = false }
            return ok
        } catch {
            return false
        }
    }

    func unlockWithPasscode(_ passcode: String) -> Bool {
        guard verifyPasscode(passcode) else { return false }
        isLocked = false
        return true
    }
}
