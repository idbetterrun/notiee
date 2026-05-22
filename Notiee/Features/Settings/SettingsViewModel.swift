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

        connectionTestStatus = .testing
        
        Task {
            do {
                if kind == .text {
                    let service = RealAIProcessingService(settingsStore: settingsStore)
                    _ = try await callTextPing(config: configuration)
                } else {
                    // 对于视觉模型，发个简单的测试图（如果支持，或者统一用文本接口 ping 端点）
                    // 为了简化，我们发一个超小的 1x1 透明图
                    _ = try await callVisionPing(config: configuration)
                }
                self.connectionTestStatus = .success(kind.readyMessage)
            } catch {
                self.connectionTestStatus = .failure("连接失败：\(error.localizedDescription)")
            }
        }
    }

    private func callTextPing(config: AIModelConfiguration) async throws -> String {
        let prompt = "Hi, this is a connection test. Please reply with 'OK' and nothing else."
        if config.activeProtocol == .openai {
            return try await OpenAICaller.callText(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, prompt: prompt)
        } else {
            return try await AnthropicCaller.callText(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, prompt: prompt)
        }
    }
    
    private func callVisionPing(config: AIModelConfiguration) async throws -> String {
        let base64Image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        let prompt = "Hi, reply 'OK'."
        if config.activeProtocol == .openai {
            return try await OpenAICaller.callVision(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, base64Image: base64Image, prompt: prompt)
        } else {
            return try await AnthropicCaller.callVision(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, base64Image: base64Image, prompt: prompt)
        }
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
