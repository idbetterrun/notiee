import Foundation
import CryptoKit
import Security

// MARK: - Login nonce (Sign in with Apple replay protection)

/// A one-shot nonce pair for a Sign in with Apple round-trip.
/// `hashed` goes on `ASAuthorizationAppleIDRequest.nonce`; `raw` is sent to the
/// backend, which recomputes `sha256(raw)` and compares it against the token's
/// `nonce` claim. This defeats identity-token replay.
struct LoginNonce: Sendable {
    let raw: String
    let hashed: String
}

// MARK: - Backend session

struct BackendSession: Sendable {
    let token: String
    let userId: String
    /// Apple only returns the email on the very first authorization.
    let email: String?
}

/// Owns the backend session for the Notiee (free) version: exchanges a Sign in
/// with Apple identity token for a backend JWT, persists it in the Keychain, and
/// exposes it to `BackendAPIClient`. In DEBUG it can bootstrap a fake session so
/// the AI pipeline is end-to-end testable before real Apple login is wired.
///
/// Notiee-target only — Notiee+ (BYOK) has no backend account.
final class AuthService: @unchecked Sendable {
    static let shared = AuthService()

    private let keychain: KeychainStore
    private let lock = NSLock()
    private var cachedToken: String?
    private var cachedUserId: String?

    private let tokenAccount = "notiee.backend.jwt"
    private let userIdAccount = "notiee.backend.userId"

    init(keychain: KeychainStore = KeychainStore(service: "com.idbetterrun.notiee.auth")) {
        self.keychain = keychain
        self.cachedToken = keychain.read(account: tokenAccount)
        self.cachedUserId = keychain.read(account: userIdAccount)
    }

    // MARK: - Token access (read by BackendAPIClient on any thread)

    var bearerToken: String? {
        lock.lock(); defer { lock.unlock() }
        return cachedToken
    }

    var userId: String? {
        lock.lock(); defer { lock.unlock() }
        return cachedUserId
    }

    var isAuthenticated: Bool { bearerToken != nil }

    // MARK: - Nonce

    /// Creates a fresh nonce pair for one login attempt.
    func makeLoginNonce() -> LoginNonce {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let raw = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let hashed = Self.sha256Hex(raw)
        return LoginNonce(raw: raw, hashed: hashed)
    }

    static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Apple login → backend session

    /// Exchanges the Apple identity token for a backend JWT. Must be called in the
    /// authorization callback, while `identityToken` is still fresh.
    @discardableResult
    func appleLogin(identityToken: String, rawNonce: String?) async throws -> BackendSession {
        var body: [String: Any] = ["identityToken": identityToken]
        if let rawNonce { body["rawNonce"] = rawNonce }
        let json = try await BackendAPIClient.shared.postJSON(path: "auth/apple", body: body, authorized: false)
        return try persistSession(from: json)
    }

    #if DEBUG
    /// DEBUG-only bootstrap: swaps a stable per-install fake token for a real
    /// backend JWT (backend must run with `ALLOW_FAKE_APPLE=1`). Lets the AI
    /// pipeline run before Sign in with Apple is fully wired. Replaced by the real
    /// `appleLogin` path in Phase 1 — same Keychain slot, so nothing else changes.
    @discardableResult
    func devLoginIfNeeded() async throws -> BackendSession? {
        if let token = bearerToken, let userId = userId {
            return BackendSession(token: token, userId: userId, email: nil)
        }
        let deviceId = DeviceIdentity.stableInstallID()
        let json = try await BackendAPIClient.shared.postJSON(
            path: "auth/apple",
            body: ["identityToken": "fake-\(deviceId)"],
            authorized: false
        )
        return try persistSession(from: json)
    }
    #endif

    // MARK: - Refresh / delete / sign out

    /// Renews an unexpired JWT (backend `/auth/refresh`). Apple can't silently
    /// re-issue an identity token, so we lean on the backend to extend a session
    /// that hasn't expired yet.
    @discardableResult
    func refresh() async throws -> BackendSession {
        let json = try await BackendAPIClient.shared.postJSON(path: "auth/refresh", body: [:], authorized: true)
        return try persistSession(from: json)
    }

    /// Deletes the backend account (removes server data + revokes on Apple's side)
    /// and clears the local session. Required by App Review 5.1.1(v).
    func deleteAccount() async throws {
        _ = try await BackendAPIClient.shared.postJSON(path: "account/delete", body: [:], authorized: true)
        signOut()
    }

    func signOut() {
        lock.lock()
        cachedToken = nil
        cachedUserId = nil
        lock.unlock()
        keychain.delete(account: tokenAccount)
        keychain.delete(account: userIdAccount)
    }

    // MARK: - Private

    private func persistSession(from json: [String: Any]) throws -> BackendSession {
        guard let token = json["token"] as? String, !token.isEmpty,
              let userId = json["userId"] as? String, !userId.isEmpty else {
            throw BackendError(code: .unknown, message: "登录响应缺少 token", httpStatus: -1, quota: nil)
        }
        let email = json["email"] as? String
        lock.lock()
        cachedToken = token
        cachedUserId = userId
        lock.unlock()
        keychain.write(account: tokenAccount, value: token)
        keychain.write(account: userIdAccount, value: userId)
        return BackendSession(token: token, userId: userId, email: email)
    }
}

// MARK: - Stable install identifier (DEBUG fake login)

enum DeviceIdentity {
    private static let key = "notiee.devInstallID"

    /// A stable random id for this install, so the DEBUG fake login maps to a
    /// consistent backend user across launches.
    static func stableInstallID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: key)
        return generated
    }
}

// MARK: - Minimal Keychain wrapper

/// Small generic-password wrapper. The backend JWT is a bearer credential and
/// must not sit in UserDefaults; the Keychain gives us at-rest protection and
/// survives reinstalls-in-place per Apple's rules.
struct KeychainStore: Sendable {
    let service: String

    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(account: String, value: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(base.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
