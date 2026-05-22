import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var defaultTab: AppTab
    @Published var textConfiguration: AIModelConfiguration
    @Published var visionConfiguration: AIModelConfiguration
    @Published private(set) var connectionTestStatus: AIConnectionTestStatus = .idle
    @Published private(set) var lastSaveError: String?

    // General
    @Published var showWeekNumbers: Bool
    @Published var firstWeekStartDay: Int
    
    // Appearance
    @Published var theme: String
    @Published var fontSize: String
    @Published var language: String
    
    // AI Toggles
    @Published var aiEnabled: Bool
    @Published var aiEnableSummary: Bool
    @Published var aiEnableDetailedContent: Bool
    @Published var aiEnableTodos: Bool
    @Published var autoProcessAfterCapture: Bool
    
    // Notifications
    @Published var notificationEnabled: Bool
    @Published var liveActivityEnabled: Bool
    @Published var notificationAdvanceTime: Int
    
    // Advanced
    @Published var customModelsEnabled: Bool
    @Published var customModels: [CustomAIModel]

    private let settingsStore: AppSettingsPersisting

    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        self.settingsStore = settingsStore
        defaultTab = settingsStore.loadDefaultTab()
        textConfiguration = settingsStore.loadConfiguration(for: .text)
        visionConfiguration = settingsStore.loadConfiguration(for: .vision)
        
        showWeekNumbers = settingsStore.loadBool(forKey: "notiee.showWeekNumbers", defaultValue: true)
        firstWeekStartDay = settingsStore.loadInt(forKey: "notiee.firstWeekStartDay", defaultValue: 2)
        theme = settingsStore.loadString(forKey: "notiee.theme", defaultValue: "system")
        fontSize = settingsStore.loadString(forKey: "notiee.fontSize", defaultValue: "medium")
        language = settingsStore.loadString(forKey: "notiee.language", defaultValue: "system")
        
        aiEnabled = settingsStore.loadBool(forKey: "notiee.aiEnabled", defaultValue: true)
        aiEnableSummary = settingsStore.loadBool(forKey: "notiee.aiEnableSummary", defaultValue: true)
        aiEnableDetailedContent = settingsStore.loadBool(forKey: "notiee.aiEnableDetailedContent", defaultValue: true)
        aiEnableTodos = settingsStore.loadBool(forKey: "notiee.aiEnableTodos", defaultValue: true)
        autoProcessAfterCapture = settingsStore.loadBool(forKey: "notiee.autoProcessAfterCapture", defaultValue: true)
        
        notificationEnabled = settingsStore.loadBool(forKey: "notiee.notificationEnabled", defaultValue: false)
        liveActivityEnabled = settingsStore.loadBool(forKey: "notiee.liveActivityEnabled", defaultValue: false)
        notificationAdvanceTime = settingsStore.loadInt(forKey: "notiee.notificationAdvanceTime", defaultValue: 5)
        
        customModelsEnabled = settingsStore.loadBool(forKey: "notiee.customModelsEnabled", defaultValue: false)
        customModels = settingsStore.loadCustomModels()
    }
    
    func saveAll() {
        settingsStore.saveBool(showWeekNumbers, forKey: "notiee.showWeekNumbers")
        settingsStore.saveInt(firstWeekStartDay, forKey: "notiee.firstWeekStartDay")
        settingsStore.saveString(theme, forKey: "notiee.theme")
        settingsStore.saveString(fontSize, forKey: "notiee.fontSize")
        settingsStore.saveString(language, forKey: "notiee.language")
        
        settingsStore.saveBool(aiEnabled, forKey: "notiee.aiEnabled")
        settingsStore.saveBool(aiEnableSummary, forKey: "notiee.aiEnableSummary")
        settingsStore.saveBool(aiEnableDetailedContent, forKey: "notiee.aiEnableDetailedContent")
        settingsStore.saveBool(aiEnableTodos, forKey: "notiee.aiEnableTodos")
        settingsStore.saveBool(autoProcessAfterCapture, forKey: "notiee.autoProcessAfterCapture")
        
        settingsStore.saveBool(notificationEnabled, forKey: "notiee.notificationEnabled")
        settingsStore.saveBool(liveActivityEnabled, forKey: "notiee.liveActivityEnabled")
        NotificationCenter.default.post(name: NSNotification.Name("LiveActivitySettingsChanged"), object: nil)
        settingsStore.saveInt(notificationAdvanceTime, forKey: "notiee.notificationAdvanceTime")
        
        settingsStore.saveBool(customModelsEnabled, forKey: "notiee.customModelsEnabled")
        settingsStore.saveCustomModels(customModels)
        
        if notificationEnabled {
            Task {
                let granted = await NotificationManager.shared.requestPermission()
                if !granted {
                    await MainActor.run {
                        self.notificationEnabled = false
                        self.settingsStore.saveBool(false, forKey: "notiee.notificationEnabled")
                    }
                }
            }
        }
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
            return try await OpenAICaller.callText(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, prompt: prompt).0
        } else {
            return try await AnthropicCaller.callText(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, prompt: prompt).0
        }
    }
    
    private func callVisionPing(config: AIModelConfiguration) async throws -> String {
        let base64Image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
        let prompt = "Hi, reply 'OK'."
        if config.activeProtocol == .openai {
            return try await OpenAICaller.callVision(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, base64Image: base64Image, prompt: prompt).0
        } else {
            return try await AnthropicCaller.callVision(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, base64Image: base64Image, prompt: prompt).0
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
