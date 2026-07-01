import Foundation
import CryptoKit

/// AES-GCM encryption for per-record content, plus passcode hashing.
///
/// Threat model: record text and images are stored as ciphertext on disk. The data
/// key (DEK) lives in the Keychain (`WhenUnlockedThisDeviceOnly`, not synced), so at
/// rest the content is unreadable without the device being unlocked. The app-lock
/// passcode / biometric gates the UI that reveals decrypted content. A future
/// enhancement could bind the DEK to a biometric Keychain ACL.
struct CryptoService {
    enum CryptoError: LocalizedError {
        case keyUnavailable
        case badCiphertext
        var errorDescription: String? {
            switch self {
            case .keyUnavailable: return "加密密钥不可用。"
            case .badCiphertext: return "密文无法解析。"
            }
        }
    }

    private let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    // MARK: - Symmetric crypto

    func encrypt(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw CryptoError.badCiphertext }
        return combined
    }

    func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    func encryptString(_ s: String) -> String {
        (try? encrypt(Data(s.utf8)))?.base64EncodedString() ?? ""
    }

    func decryptString(_ base64: String) throws -> String {
        guard let data = Data(base64Encoded: base64) else { throw CryptoError.badCiphertext }
        return String(decoding: try decrypt(data), as: UTF8.self)
    }

    // MARK: - Keychain-backed DEK

    private static let dekKeychainKey = "notiee.security.dek"

    /// Returns the shared record-encryption service, creating & persisting a DEK on first use.
    static func shared(secretStore: SecretPersisting = KeychainSecretStore()) -> CryptoService {
        if let b64 = secretStore.string(forKey: dekKeychainKey),
           let raw = Data(base64Encoded: b64) {
            return CryptoService(key: SymmetricKey(data: raw))
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        try? secretStore.setString(raw.base64EncodedString(), forKey: dekKeychainKey)
        return CryptoService(key: key)
    }

    // MARK: - Passcode hashing

    static func makeSalt() -> String {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    static func hashPasscode(_ passcode: String, salt: String) -> String {
        let input = Data((salt + ":" + passcode).utf8)
        return Data(SHA256.hash(data: input)).base64EncodedString()
    }

    static func verifyPasscode(_ passcode: String, salt: String, expectedHash: String) -> Bool {
        hashPasscode(passcode, salt: salt) == expectedHash
    }
}
