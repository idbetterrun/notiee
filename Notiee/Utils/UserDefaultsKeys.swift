import Foundation

/// Centralized UserDefaults key constants for Notiee.
/// Replaces all bare string literals scattered across the codebase.
enum UDK {
    // MARK: - App State
    static let hasAgreedToPrivacy = "hasAgreedToPrivacy"
    static let hasSeenWelcome = "hasSeenWelcome"
    static let hasSeenPermissions = "hasSeenPermissions"
    static let lastAppVersion = "lastAppVersion"

    // MARK: - General
    static let defaultTab = "notiee.defaultTab"
    static let scenePreset = "notiee.scenePreset"

    // MARK: - Appearance
    static let theme = "notiee.theme"
    static let fontSize = "notiee.fontSize"
    static let language = "notiee.language"
    static let accentColor = "notiee.accentColor"

    // MARK: - Calendar & Schedule
    static let showWeekNumbers = "notiee.showWeekNumbers"
    static let firstWeekStartDay = "notiee.firstWeekStartDay"
    static let semesterStartDate = "notiee.semesterStartDate"
    static let selectedCalendarIdentifiers = "notiee.selectedCalendarIdentifiers"
    static let courseCalendarIdentifiers = "notiee.courseCalendarIdentifiers"
    static let ignoredCalendarEventKeys = "notiee.ignoredCalendarEventKeys"

    // MARK: - AI Settings
    static let aiEnabled = "notiee.aiEnabled"
    static let autoProcessAfterCapture = "notiee.autoProcessAfterCapture"
    static let aiEnableSummary = "notiee.aiEnableSummary"
    static let aiEnableDetailedContent = "notiee.aiEnableDetailedContent"
    static let aiEnableTodos = "notiee.aiEnableTodos"

    // MARK: - AI Model Config (parameterized)
    static func aiProviderType(for kind: AIModelKind) -> String {
        "notiee.ai.\(kind.rawValue).providerType"
    }
    static func aiCustomEndpoint(for kind: AIModelKind) -> String {
        "notiee.ai.\(kind.rawValue).customEndpoint"
    }
    static func aiCustomProtocol(for kind: AIModelKind) -> String {
        "notiee.ai.\(kind.rawValue).customProtocol"
    }
    static func aiModelName(for kind: AIModelKind) -> String {
        "notiee.ai.\(kind.rawValue).modelName"
    }
    static func aiApiKey(for kind: AIModelKind) -> String {
        "notiee.ai.\(kind.rawValue).apiKey"
    }

    // MARK: - AI Token Tracking
    static let tokenWarningThreshold = "notiee.tokenWarningThreshold"
    static let accumulatedDeletedTokens = "notiee.accumulatedDeletedTokens"

    // MARK: - Custom Models
    static let customModels = "notiee.customModels"

    // MARK: - Notifications
    static let notificationEnabled = "notiee.notificationEnabled"
    static let notificationAdvanceTime = "notiee.notificationAdvanceTime"
    static let liveActivityEnabled = "notiee.liveActivityEnabled"
    static let liveActivityDisabledEventIDs = "notiee.liveActivityDisabledEventIDs"

    // MARK: - iCloud
    static let icloudLastSyncDate = "notiee.icloudLastSyncDate"

    // MARK: - Spark Token Tracking
    static let sparkAccumulatedTokens = "notiee.sparkAccumulatedTokens"


    // MARK: - Spark
    static let sparkCustomStyle = "spark_custom_style"
    static let sparkCustomStyles = "spark_custom_styles"
    static let sparkLastMemoryCompressionRounds = "spark_last_memory_compression_rounds"
    static let sparkCurrentConversationId = "spark_current_conversation_id"

    // MARK: - Spark Agent
    static let sparkAgentTrustLevel = "spark_agent_trust_level"
    static let sparkAgentMaxIterations = "spark_agent_max_iterations"
    static let sparkAgentMaxToolsPerRound = "spark_agent_max_tools_per_round"
    static let sparkAgentUndoTTLMinutes = "spark_agent_undo_ttl_minutes"
    static let sparkAgentHistoryRetentionDays = "spark_agent_history_retention_days"
    static let sparkAgentTokenWarning = "spark_agent_token_warning"
    static let sparkModelOverride = "spark_model_override"
    static let sparkThinkingLevel = "spark_thinking_level"

    // MARK: - Security
    static let securityAppLockEnabled = "notiee.security.appLockEnabled"
    static let securityBiometricEnabled = "notiee.security.biometricEnabled"
    static let securityAutoLockGraceSeconds = "notiee.security.autoLockGraceSeconds"

    // MARK: - Lab Features
    static let labMarkdownRenderingEnabled = "labMarkdownRenderingEnabled"
    static let labFullVisionModeEnabled = "labFullVisionModeEnabled"
    static let labDeepAssociationModeEnabled = "labDeepAssociationModeEnabled"
    static let labLowConsumptionModeEnabled = "labLowConsumptionModeEnabled"
    static let labRecordOutputLanguage = "labRecordOutputLanguage"
}
