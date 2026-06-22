import Foundation

enum AgentTrustLevel: String, CaseIterable, Codable, Sendable {
    case cautious
    case standard
    case full
}

extension AgentToolPermission {
    func isAllowed(by trustLevel: AgentTrustLevel) -> Bool {
        switch (self, trustLevel) {
        case (.read, _):             return true
        case (.write, .cautious):    return false
        case (.write, _):            return true
        case (.destructive, .full):  return true
        case (.destructive, _):      return false
        }
    }
}

@MainActor
final class AgentTrustManager: ObservableObject {
    @Published var currentLevel: AgentTrustLevel = .standard

    private let settingsStore: AppSettingsPersisting

    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        self.settingsStore = settingsStore
        loadSavedSettings()
    }

    func setLevel(_ level: AgentTrustLevel) {
        currentLevel = level
        settingsStore.saveString(level.rawValue, forKey: UDK.sparkAgentTrustLevel)
    }

    private func loadSavedSettings() {
        let raw = settingsStore.loadString(forKey: UDK.sparkAgentTrustLevel, defaultValue: AgentTrustLevel.standard.rawValue)
        if let level = AgentTrustLevel(rawValue: raw) {
            currentLevel = level
        }
    }
}
