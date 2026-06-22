import Foundation

/// Models that error unless their thinking/reasoning mode is enabled.
/// For these, the thinking level is forced and the UI control is locked.
enum ModelThinkingPolicy {
    /// Returns the forced `ThinkingLevel.id` when the given provider+model
    /// must run with thinking enabled, or `nil` when the user may choose freely.
    static func forcedThinkingLevelID(provider: AIProviderType, model: String) -> String? {
        switch (provider, model) {
        case (.deepseek, "deepseek-v4-pro"):
            return "on"
        default:
            return nil
        }
    }
}
