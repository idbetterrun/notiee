import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var defaultTab: AppTab
    @Published var textConfiguration: AIModelConfiguration
    @Published var visionConfiguration: AIModelConfiguration
    @Published private(set) var connectionTestStatus: AIConnectionTestStatus = .idle
    @Published private(set) var lastSaveError: String?

    private let settingsStore: AppSettingsPersisting

    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        self.settingsStore = settingsStore
        defaultTab = settingsStore.loadDefaultTab()
        textConfiguration = settingsStore.loadConfiguration(for: .text)
        visionConfiguration = settingsStore.loadConfiguration(for: .vision)
    }

    func saveDefaultTab() {
        settingsStore.saveDefaultTab(defaultTab)
    }

    func saveTextConfiguration() {
        saveConfiguration(for: .text)
    }

    func saveVisionConfiguration() {
        saveConfiguration(for: .vision)
    }

    func testConnection(for kind: AIModelKind) {
        let configuration = configuration(for: kind).normalized
        guard configuration.isComplete else {
            connectionTestStatus = .failure("请先填写 API Key、模型名称和接口地址。")
            return
        }

        connectionTestStatus = .success(kind.readyMessage)
    }

    private func saveConfiguration(for kind: AIModelKind) {
        let configuration = configuration(for: kind).normalized

        do {
            try settingsStore.saveConfiguration(configuration, for: kind)
            setConfiguration(configuration, for: kind)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    private func configuration(for kind: AIModelKind) -> AIModelConfiguration {
        switch kind {
        case .text:
            textConfiguration
        case .vision:
            visionConfiguration
        }
    }

    private func setConfiguration(_ configuration: AIModelConfiguration, for kind: AIModelKind) {
        switch kind {
        case .text:
            textConfiguration = configuration
        case .vision:
            visionConfiguration = configuration
        }
    }
}
