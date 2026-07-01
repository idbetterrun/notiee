import XCTest
@testable import Notiee

final class CustomModelKeychainTests: XCTestCase {
    private final class InMemorySecrets: SecretPersisting {
        var storage: [String: String] = [:]
        func string(forKey key: String) -> String? { storage[key] }
        func setString(_ value: String, forKey key: String) throws { storage[key] = value }
        func removeString(forKey key: String) throws { storage[key] = nil }
    }

    private func makeStore() -> (UserDefaultsAppSettingsStore, UserDefaults, InMemorySecrets) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let secrets = InMemorySecrets()
        let store = UserDefaultsAppSettingsStore(userDefaults: defaults, secretStore: secrets)
        return (store, defaults, secrets)
    }

    func testSave_writesKeyToKeychain_andBlanksBlob() throws {
        let (store, defaults, secrets) = makeStore()
        let model = CustomAIModel(name: "m", kind: .text, endpoint: "https://x",
                                  protocolType: .openai, modelIdentifier: "gpt", apiKey: "sk-SECRET")
        store.saveCustomModels([model])

        XCTAssertTrue(secrets.storage.values.contains("sk-SECRET"))
        let raw = defaults.data(forKey: "notiee.customModels")!
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("sk-SECRET"))
    }

    func testLoad_restoresKeyFromKeychain() throws {
        let (store, _, _) = makeStore()
        let model = CustomAIModel(name: "m", kind: .text, endpoint: "https://x",
                                  protocolType: .openai, modelIdentifier: "gpt", apiKey: "sk-SECRET")
        store.saveCustomModels([model])

        let loaded = store.loadCustomModels()
        XCTAssertEqual(loaded.first?.apiKey, "sk-SECRET")
    }

    func testLoad_migratesLegacyPlaintextBlob() throws {
        let (store, defaults, secrets) = makeStore()
        let legacy = CustomAIModel(name: "m", kind: .text, endpoint: "https://x",
                                    protocolType: .openai, modelIdentifier: "gpt", apiKey: "sk-LEGACY")
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "notiee.customModels")

        let loaded = store.loadCustomModels()

        XCTAssertEqual(loaded.first?.apiKey, "sk-LEGACY")
        XCTAssertTrue(secrets.storage.values.contains("sk-LEGACY"), "load 应把存量明文迁移进 Keychain")
        let raw = defaults.data(forKey: "notiee.customModels")!
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("sk-LEGACY"), "迁移后 blob 应抹空明文")
    }

    func testSave_removesKeychainEntryForDeletedModel() throws {
        let (store, _, secrets) = makeStore()
        let a = CustomAIModel(name: "a", kind: .text, endpoint: "https://x",
                              protocolType: .openai, modelIdentifier: "gpt", apiKey: "sk-A")
        store.saveCustomModels([a])
        XCTAssertTrue(secrets.storage.values.contains("sk-A"))

        store.saveCustomModels([])
        XCTAssertFalse(secrets.storage.values.contains("sk-A"), "删除模型应清理其 Keychain 条目")
    }
}
