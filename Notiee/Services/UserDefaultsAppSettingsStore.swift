import Foundation
import Security

protocol AppSettingsPersisting {
    func loadDefaultTab() -> AppTab
    func saveDefaultTab(_ tab: AppTab)
    func loadConfiguration(for kind: AIModelKind) -> AIModelConfiguration
    func saveConfiguration(_ configuration: AIModelConfiguration, for kind: AIModelKind) throws
}

protocol SecretPersisting {
    func string(forKey key: String) -> String?
    func setString(_ value: String, forKey key: String) throws
    func removeString(forKey key: String) throws
}

struct UserDefaultsAppSettingsStore: AppSettingsPersisting {
    static let live = UserDefaultsAppSettingsStore()

    private let userDefaults: UserDefaults
    private let secretStore: SecretPersisting

    init(
        userDefaults: UserDefaults = .standard,
        secretStore: SecretPersisting = KeychainSecretStore()
    ) {
        self.userDefaults = userDefaults
        self.secretStore = secretStore
    }

    func loadDefaultTab() -> AppTab {
        guard
            let rawValue = userDefaults.string(forKey: Keys.defaultTab),
            let tab = AppTab(rawValue: rawValue)
        else {
            return .today
        }

        return tab
    }

    func saveDefaultTab(_ tab: AppTab) {
        userDefaults.set(tab.rawValue, forKey: Keys.defaultTab)
    }

    func loadConfiguration(for kind: AIModelKind) -> AIModelConfiguration {
        AIModelConfiguration(
            providerName: userDefaults.string(forKey: Keys.providerName(for: kind)) ?? "OpenAI Compatible",
            endpoint: userDefaults.string(forKey: Keys.endpoint(for: kind)) ?? "",
            modelName: userDefaults.string(forKey: Keys.modelName(for: kind)) ?? "",
            apiKey: secretStore.string(forKey: Keys.apiKey(for: kind)) ?? ""
        )
    }

    func saveConfiguration(_ configuration: AIModelConfiguration, for kind: AIModelKind) throws {
        let normalized = configuration.normalized
        userDefaults.set(normalized.providerName, forKey: Keys.providerName(for: kind))
        userDefaults.set(normalized.endpoint, forKey: Keys.endpoint(for: kind))
        userDefaults.set(normalized.modelName, forKey: Keys.modelName(for: kind))

        if normalized.apiKey.isEmpty {
            try secretStore.removeString(forKey: Keys.apiKey(for: kind))
        } else {
            try secretStore.setString(normalized.apiKey, forKey: Keys.apiKey(for: kind))
        }
    }
}

struct KeychainSecretStore: SecretPersisting {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.notiee.app") {
        self.service = service
    }

    func string(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func setString(_ value: String, forKey key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(forKey: key)
        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecretStoreError.unhandledStatus(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw SecretStoreError.unhandledStatus(updateStatus)
        }
    }

    func removeString(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unhandledStatus(status)
        }
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

enum SecretStoreError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            "Keychain 操作失败：\(status)"
        }
    }
}

private enum Keys {
    static let defaultTab = "notiee.defaultTab"

    static func providerName(for kind: AIModelKind) -> String {
        "notiee.ai.\(kind.rawValue).providerName"
    }

    static func endpoint(for kind: AIModelKind) -> String {
        "notiee.ai.\(kind.rawValue).endpoint"
    }

    static func modelName(for kind: AIModelKind) -> String {
        "notiee.ai.\(kind.rawValue).modelName"
    }

    static func apiKey(for kind: AIModelKind) -> String {
        "notiee.ai.\(kind.rawValue).apiKey"
    }
}
