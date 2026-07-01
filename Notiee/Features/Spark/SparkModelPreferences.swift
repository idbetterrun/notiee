import Foundation

final class SparkModelPreferences {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var modelOverride: String {
        userDefaults.string(forKey: UDK.sparkModelOverride) ?? ""
    }

    func setModelOverride(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            userDefaults.removeObject(forKey: UDK.sparkModelOverride)
        } else {
            userDefaults.set(trimmed, forKey: UDK.sparkModelOverride)
        }
    }

    func effectiveModelName(globalModel: String) -> String {
        modelOverride.isEmpty ? globalModel : modelOverride
    }

    var thinkingLevelID: String? {
        userDefaults.string(forKey: UDK.sparkThinkingLevel)
    }

    func setThinkingLevelID(_ id: String) {
        userDefaults.set(id, forKey: UDK.sparkThinkingLevel)
    }
}
