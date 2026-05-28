import Combine
import EventKit
import Foundation
import UIKit

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var defaultTab: AppTab
    @Published var textConfiguration: AIModelConfiguration
    @Published var visionConfiguration: AIModelConfiguration
    @Published private(set) var textConnectionTestStatus: AIConnectionTestStatus = .idle
    @Published private(set) var visionConnectionTestStatus: AIConnectionTestStatus = .idle
    @Published private(set) var lastSaveError: String?

    // General
    @Published var showWeekNumbers: Bool
    @Published var semesterStartDate: Date?
    @Published var firstWeekStartDay: Int
    
    // Appearance
    @Published var theme: String
    @Published var fontSize: String
    @Published var language: String
    @Published var scenePreset: ScenePreset
    @Published var accentColor: String
    
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
    @Published var tokenWarningThreshold: Int
    
    // Calendar Selection
    @Published var availableCalendars: [EKCalendar] = []
    @Published var selectedCalendarIDs: Set<String> = []

    // Advanced
    @Published var customModels: [CustomAIModel]
    @Published var selectedCustomModelID: UUID?

    private let settingsStore: AppSettingsPersisting

    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        self.settingsStore = settingsStore
        defaultTab = settingsStore.loadDefaultTab()
        textConfiguration = settingsStore.loadConfiguration(for: .text)
        visionConfiguration = settingsStore.loadConfiguration(for: .vision)
        
        showWeekNumbers = settingsStore.loadBool(forKey: "notiee.showWeekNumbers", defaultValue: true)
        firstWeekStartDay = settingsStore.loadInt(forKey: "notiee.firstWeekStartDay", defaultValue: 2)
        if let timeInterval = UserDefaults.standard.object(forKey: "notiee.semesterStartDate") as? TimeInterval {
            semesterStartDate = Date(timeIntervalSince1970: timeInterval)
        }
        theme = settingsStore.loadString(forKey: "notiee.theme", defaultValue: "system")
        fontSize = settingsStore.loadString(forKey: "notiee.fontSize", defaultValue: "medium")
        language = settingsStore.loadString(forKey: "notiee.language", defaultValue: "system")
        scenePreset = ScenePreset.load()
        accentColor = settingsStore.loadString(forKey: "notiee.accentColor", defaultValue: "default")
        
        aiEnabled = settingsStore.loadBool(forKey: "notiee.aiEnabled", defaultValue: true)
        aiEnableSummary = settingsStore.loadBool(forKey: "notiee.aiEnableSummary", defaultValue: true)
        aiEnableDetailedContent = settingsStore.loadBool(forKey: "notiee.aiEnableDetailedContent", defaultValue: true)
        aiEnableTodos = settingsStore.loadBool(forKey: "notiee.aiEnableTodos", defaultValue: true)
        autoProcessAfterCapture = settingsStore.loadBool(forKey: "notiee.autoProcessAfterCapture", defaultValue: true)
        
        notificationEnabled = settingsStore.loadBool(forKey: "notiee.notificationEnabled", defaultValue: false)
        liveActivityEnabled = settingsStore.loadBool(forKey: "notiee.liveActivityEnabled", defaultValue: false)
        notificationAdvanceTime = settingsStore.loadInt(forKey: "notiee.notificationAdvanceTime", defaultValue: 5)
        tokenWarningThreshold = settingsStore.loadInt(forKey: "notiee.tokenWarningThreshold", defaultValue: 0)
        
        customModels = settingsStore.loadCustomModels()
        loadCalendarSelection()
    }
    
    func loadCalendarSelection() {
        availableCalendars = CalendarService.shared.availableCalendars
        selectedCalendarIDs = CalendarService.shared.selectedCalendarIDs()
    }
    
    func toggleCalendar(_ id: String) {
        if selectedCalendarIDs.contains(id) {
            selectedCalendarIDs.remove(id)
        } else {
            selectedCalendarIDs.insert(id)
        }
        CalendarService.shared.saveSelectedCalendarIDs(selectedCalendarIDs)
    }
    
    func saveAll() {
        settingsStore.saveBool(showWeekNumbers, forKey: "notiee.showWeekNumbers")
        settingsStore.saveInt(firstWeekStartDay, forKey: "notiee.firstWeekStartDay")
        if let date = semesterStartDate {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "notiee.semesterStartDate")
        } else {
            UserDefaults.standard.removeObject(forKey: "notiee.semesterStartDate")
        }
        settingsStore.saveString(theme, forKey: "notiee.theme")
        settingsStore.saveString(fontSize, forKey: "notiee.fontSize")
        settingsStore.saveString(language, forKey: "notiee.language")
        settingsStore.saveString(accentColor, forKey: "notiee.accentColor")
        scenePreset.save()
        
        if language == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([language], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()
        
        settingsStore.saveBool(aiEnabled, forKey: "notiee.aiEnabled")
        settingsStore.saveBool(aiEnableSummary, forKey: "notiee.aiEnableSummary")
        settingsStore.saveBool(aiEnableDetailedContent, forKey: "notiee.aiEnableDetailedContent")
        settingsStore.saveBool(aiEnableTodos, forKey: "notiee.aiEnableTodos")
        settingsStore.saveBool(autoProcessAfterCapture, forKey: "notiee.autoProcessAfterCapture")
        
        settingsStore.saveBool(notificationEnabled, forKey: "notiee.notificationEnabled")
        settingsStore.saveBool(liveActivityEnabled, forKey: "notiee.liveActivityEnabled")
        NotificationCenter.default.post(name: NSNotification.Name("LiveActivitySettingsChanged"), object: nil)
        settingsStore.saveInt(notificationAdvanceTime, forKey: "notiee.notificationAdvanceTime")
        settingsStore.saveInt(tokenWarningThreshold, forKey: "notiee.tokenWarningThreshold")
        
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

    func applyCustomModel(_ model: CustomAIModel, for kind: AIModelKind) {
        let config = AIModelConfiguration(
            providerType: .custom,
            customEndpoint: model.endpoint,
            customProtocol: model.protocolType,
            modelName: model.modelIdentifier,
            apiKey: model.apiKey
        )
        setConfiguration(config, for: kind)
        saveConfiguration(for: kind)
    }

    func testConnection(for kind: AIModelKind) {
        let configuration = configuration(for: kind).normalized
        guard configuration.isComplete else {
            switch kind {
            case .text:
                textConnectionTestStatus = .failure("请先填写 API Key、模型名称和接口地址。")
            case .vision:
                visionConnectionTestStatus = .failure("请先填写 API Key、模型名称和接口地址。")
            }
            return
        }

        switch kind {
        case .text:
            textConnectionTestStatus = .testing
        case .vision:
            visionConnectionTestStatus = .testing
        }
        
        Task {
            do {
                if kind == .text {
                    _ = try await callTextPing(config: configuration)
                } else {
                    _ = try await callVisionPing(config: configuration)
                }
                switch kind {
                case .text:
                    self.textConnectionTestStatus = .success(kind.readyMessage)
                case .vision:
                    self.visionConnectionTestStatus = .success(kind.readyMessage)
                }
            } catch {
                switch kind {
                case .text:
                    self.textConnectionTestStatus = .failure("连接失败：\(error.localizedDescription)")
                case .vision:
                    self.visionConnectionTestStatus = .failure("连接失败：\(error.localizedDescription)")
                }
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
        let base64Image = generateTestImageBase64()
        let prompt = "Hi, reply 'OK'."
        if config.activeProtocol == .openai {
            return try await OpenAICaller.callVision(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, base64Image: base64Image, prompt: prompt).0
        } else {
            return try await AnthropicCaller.callVision(endpoint: config.activeEndpoint, model: config.modelName, apiKey: config.apiKey, base64Image: base64Image, prompt: prompt).0
        }
    }

    private func generateTestImageBase64() -> String {
        let size = CGSize(width: 15, height: 15)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 15))
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 8, y: 0, width: 7, height: 15))
        }
        return image.jpegData(compressionQuality: 0.8)?.base64EncodedString() ?? ""
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
