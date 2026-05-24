import XCTest
@testable import Notiee

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testDefaultTabPersistsAndReloads() {
        let defaults = isolatedUserDefaults()
        let store = UserDefaultsAppSettingsStore(
            userDefaults: defaults,
            secretStore: InMemorySecretStore()
        )
        let viewModel = SettingsViewModel(settingsStore: store)

        XCTAssertEqual(viewModel.defaultTab, .today)

        viewModel.defaultTab = .records
        viewModel.saveDefaultTab()

        let reloadedViewModel = SettingsViewModel(settingsStore: store)
        XCTAssertEqual(reloadedViewModel.defaultTab, .records)
    }

    func testAIConfigurationPersistsSecretOutsideUserDefaults() throws {
        let defaults = isolatedUserDefaults()
        let secretStore = InMemorySecretStore()
        let store = UserDefaultsAppSettingsStore(userDefaults: defaults, secretStore: secretStore)
        let configuration = AIModelConfiguration(
            providerType: .custom,
            customEndpoint: "https://api.example.com/v1",
            modelName: "notiee-text",
            apiKey: "sk-notiee-secret"
        )

        try store.saveConfiguration(configuration, for: .text)

        XCTAssertEqual(store.loadConfiguration(for: .text), configuration)
        XCTAssertEqual(secretStore.string(forKey: "notiee.ai.text.apiKey"), "sk-notiee-secret")
        let defaultsSnapshot = defaults.dictionaryRepresentation()
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
        XCTAssertFalse(defaultsSnapshot.contains("sk-notiee-secret"))
    }

    func testConnectionStatusRequiresCompleteConfiguration() {
        let store = UserDefaultsAppSettingsStore(
            userDefaults: isolatedUserDefaults(),
            secretStore: InMemorySecretStore()
        )
        let viewModel = SettingsViewModel(settingsStore: store)

        viewModel.textConfiguration = AIModelConfiguration(
            providerType: .custom,
            customEndpoint: "https://api.example.com/v1",
            modelName: "notiee-text",
            apiKey: ""
        )
        viewModel.testConnection(for: .text)
        XCTAssertEqual(viewModel.textConnectionTestStatus, .failure("请先填写 API Key、模型名称和接口地址。"))

        viewModel.textConfiguration.apiKey = "sk-notiee-secret"
        viewModel.testConnection(for: .text)
        XCTAssertEqual(viewModel.textConnectionTestStatus, .testing)
    }

    private func isolatedUserDefaults() -> UserDefaults {
        let suiteName = "NotieeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class InMemorySecretStore: SecretPersisting {
    private var values: [String: String] = [:]

    func string(forKey key: String) -> String? {
        values[key]
    }

    func setString(_ value: String, forKey key: String) throws {
        values[key] = value
    }

    func removeString(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}
