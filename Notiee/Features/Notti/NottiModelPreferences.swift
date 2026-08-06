import Foundation

final class NottiModelPreferences {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var modelOverride: String {
        userDefaults.string(forKey: UDK.nottiModelOverride) ?? ""
    }

    func setModelOverride(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            userDefaults.removeObject(forKey: UDK.nottiModelOverride)
        } else {
            userDefaults.set(trimmed, forKey: UDK.nottiModelOverride)
        }
    }

    func effectiveModelName(globalModel: String) -> String {
        modelOverride.isEmpty ? globalModel : modelOverride
    }

    var thinkingLevelID: String? {
        userDefaults.string(forKey: UDK.nottiThinkingLevel)
    }

    func setThinkingLevelID(_ id: String) {
        userDefaults.set(id, forKey: UDK.nottiThinkingLevel)
    }
}
