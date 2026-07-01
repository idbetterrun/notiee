import Foundation
import Security

protocol AppSettingsPersisting {
    func loadDefaultTab() -> AppTab
    func saveDefaultTab(_ tab: AppTab)
    func loadConfiguration(for kind: AIModelKind) -> AIModelConfiguration
    func saveConfiguration(_ configuration: AIModelConfiguration, for kind: AIModelKind) throws
    
    func loadBool(forKey key: String, defaultValue: Bool) -> Bool
    func saveBool(_ value: Bool, forKey key: String)
    func loadInt(forKey key: String, defaultValue: Int) -> Int
    func saveInt(_ value: Int, forKey key: String)
    func loadString(forKey key: String, defaultValue: String) -> String
    func saveString(_ value: String, forKey key: String)
    
    // Custom models
    func loadCustomModels() -> [CustomAIModel]
    func saveCustomModels(_ models: [CustomAIModel])
}

struct CustomAIModel: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: AIModelKind
    var endpoint: String
    var protocolType: AIProtocol
    var modelIdentifier: String
    var apiKey: String
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
        let providerTypeStr = userDefaults.string(forKey: Keys.providerType(for: kind)) ?? ""
        let providerType = AIProviderType(rawValue: providerTypeStr) ?? (kind == .text ? .qwenText : .qwenVision)
        let customProtocolStr = userDefaults.string(forKey: Keys.customProtocol(for: kind)) ?? ""
        let customProtocol = AIProtocol(rawValue: customProtocolStr) ?? .openai
        
        return AIModelConfiguration(
            providerType: providerType,
            customEndpoint: userDefaults.string(forKey: Keys.customEndpoint(for: kind)) ?? "",
            customProtocol: customProtocol,
            modelName: userDefaults.string(forKey: Keys.modelName(for: kind)) ?? "",
            apiKey: secretStore.string(forKey: Keys.apiKey(for: kind)) ?? ""
        )
    }

    func saveConfiguration(_ configuration: AIModelConfiguration, for kind: AIModelKind) throws {
        let normalized = configuration.normalized
        userDefaults.set(normalized.providerType.rawValue, forKey: Keys.providerType(for: kind))
        userDefaults.set(normalized.customEndpoint, forKey: Keys.customEndpoint(for: kind))
        userDefaults.set(normalized.customProtocol.rawValue, forKey: Keys.customProtocol(for: kind))
        userDefaults.set(normalized.modelName, forKey: Keys.modelName(for: kind))

        if normalized.apiKey.isEmpty {
            try secretStore.removeString(forKey: Keys.apiKey(for: kind))
        } else {
            try secretStore.setString(normalized.apiKey, forKey: Keys.apiKey(for: kind))
        }
    }

    func loadBool(forKey key: String, defaultValue: Bool) -> Bool {
        if userDefaults.object(forKey: key) == nil { return defaultValue }
        return userDefaults.bool(forKey: key)
    }
    
    func saveBool(_ value: Bool, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func loadInt(forKey key: String, defaultValue: Int) -> Int {
        if userDefaults.object(forKey: key) == nil { return defaultValue }
        return userDefaults.integer(forKey: key)
    }
    
    func saveInt(_ value: Int, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }
    
    func loadString(forKey key: String, defaultValue: String) -> String {
        return userDefaults.string(forKey: key) ?? defaultValue
    }
    
    func saveString(_ value: String, forKey key: String) {
        userDefaults.set(value, forKey: key)
    }

    private func customModelKeychainKey(_ id: UUID) -> String {
        "customModel.apiKey.\(id.uuidString)"
    }

    func loadCustomModels() -> [CustomAIModel] {
        guard let data = userDefaults.data(forKey: UDK.customModels),
              var models = try? JSONDecoder().decode([CustomAIModel].self, from: data) else {
            return []
        }
        var needsMigration = false
        for i in models.indices {
            if let stored = secretStore.string(forKey: customModelKeychainKey(models[i].id)) {
                models[i].apiKey = stored
            } else if !models[i].apiKey.isEmpty {
                needsMigration = true
            }
        }
        if needsMigration {
            saveCustomModels(models)
        }
        return models
    }

    func saveCustomModels(_ models: [CustomAIModel]) {
        if let oldData = userDefaults.data(forKey: UDK.customModels),
           let oldModels = try? JSONDecoder().decode([CustomAIModel].self, from: oldData) {
            let newIDs = Set(models.map { $0.id })
            for old in oldModels where !newIDs.contains(old.id) {
                try? secretStore.removeString(forKey: customModelKeychainKey(old.id))
            }
        }
        var sanitized = models
        for i in sanitized.indices {
            let key = customModelKeychainKey(sanitized[i].id)
            if sanitized[i].apiKey.isEmpty {
                try? secretStore.removeString(forKey: key)
            } else {
                try? secretStore.setString(sanitized[i].apiKey, forKey: key)
            }
            sanitized[i].apiKey = ""
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            userDefaults.set(data, forKey: UDK.customModels)
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
    static let defaultTab = UDK.defaultTab

    static func providerType(for kind: AIModelKind) -> String {
        UDK.aiProviderType(for: kind)
    }

    static func customEndpoint(for kind: AIModelKind) -> String {
        UDK.aiCustomEndpoint(for: kind)
    }

    static func customProtocol(for kind: AIModelKind) -> String {
        UDK.aiCustomProtocol(for: kind)
    }

    static func modelName(for kind: AIModelKind) -> String {
        UDK.aiModelName(for: kind)
    }

    static func apiKey(for kind: AIModelKind) -> String {
        UDK.aiApiKey(for: kind)
    }
}
