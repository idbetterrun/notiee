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

    // MARK: - Backend (Notiee free version)
    /// Optional runtime override for the backend base URL (e.g. a LAN dev box).
    /// Empty/unset → compile-time default in `BackendAPIClient`.
    static let backendBaseURL = "notiee.backendBaseURL"

    /// Set on the first launch after (re)install. UserDefaults is wiped when the
    /// app is deleted, but the Keychain is NOT — so its absence marks a fresh
    /// install and triggers a one-time purge of any stale Keychain session,
    /// preventing a reinstalled app from appearing "logged in" with old quota.
    static let hasBootstrappedInstall = "notiee.hasBootstrappedInstall"

    // MARK: - Curated model selection (Notiee free version)
    /// 免费版选中的文本 / 视觉模型 ID（对应后端 MODEL_CATALOG 的 key）。
    /// 未设置或对当前档位非法时，读取端会夹取回免费默认模型。
    static let selectedTextModel = "notiee.selectedTextModel"
    static let selectedVisionModel = "notiee.selectedVisionModel"

    /// 当前档位缓存（"free"/"pro"）。持久化，供任意线程同步读取以驱动 UI 门控。
    /// 真值在后端，仅 UI 用；由 EntitlementStore 写入。
    static let entitlementTier = "notiee.entitlementTier"

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

    // MARK: - Notti Token Tracking
    static let nottiAccumulatedTokens = "notiee.nottiAccumulatedTokens"


    // MARK: - Notti
    static let nottiCustomStyle = "notti_custom_style"
    static let nottiCustomStyles = "notti_custom_styles"
    static let nottiCurrentConversationId = "notti_current_conversation_id"

    // MARK: - Notti Agent
    static let nottiAgentTrustLevel = "notti_agent_trust_level"
    static let nottiAgentMaxIterations = "notti_agent_max_iterations"
    static let nottiAgentMaxToolsPerRound = "notti_agent_max_tools_per_round"
    static let nottiAgentUndoTTLMinutes = "notti_agent_undo_ttl_minutes"
    static let nottiAgentHistoryRetentionDays = "notti_agent_history_retention_days"
    static let nottiAgentTokenWarning = "notti_agent_token_warning"
    static let nottiModelOverride = "notti_model_override"
    static let nottiThinkingLevel = "notti_thinking_level"
    static let nottiAutomaticMemoryEnabled = "notti.memory.automatic.enabled"
    static let nottiMemoryUseEnabled = "notti.memory.use.enabled"
    static let nottiMemoryPrivacyNoticeVersion = "notti.memory.privacy.version"
    static let nottiMemoryMigrationVersion = "notti.memory.migration.version"
    /// Keychain account for the Bocha web-search API key (BYOK, Plus-only).
    static let bochaSearchAPIKey = "notti.websearch.bocha.apiKey"

    // Explicit one-release compatibility keys. Do not use these for new writes.
    static let legacySparkAccumulatedTokens = "notiee.sparkAccumulatedTokens"
    static let legacySparkCustomStyle = "spark_custom_style"
    static let legacySparkCustomStyles = "spark_custom_styles"
    static let legacySparkCurrentConversationId = "spark_current_conversation_id"
    static let legacySparkAgentTrustLevel = "spark_agent_trust_level"
    static let legacySparkAgentMaxIterations = "spark_agent_max_iterations"
    static let legacySparkAgentMaxToolsPerRound = "spark_agent_max_tools_per_round"
    static let legacySparkAgentUndoTTLMinutes = "spark_agent_undo_ttl_minutes"
    static let legacySparkAgentHistoryRetentionDays = "spark_agent_history_retention_days"
    static let legacySparkAgentTokenWarning = "spark_agent_token_warning"
    static let legacySparkModelOverride = "spark_model_override"
    static let legacySparkThinkingLevel = "spark_thinking_level"
    static let legacySparkBochaSearchAPIKey = "spark.websearch.bocha.apiKey"

    // MARK: - Security
    static let securityAppLockEnabled = "notiee.security.appLockEnabled"
    static let securityBiometricEnabled = "notiee.security.biometricEnabled"
    static let securityAutoLockGraceSeconds = "notiee.security.autoLockGraceSeconds"
    static let securityRequireEncryptedDeleteAuth = "notiee.security.requireEncryptedDeleteAuth"

    // MARK: - Lab Features
    static let labMarkdownRenderingEnabled = "labMarkdownRenderingEnabled"
    static let labFullVisionModeEnabled = "labFullVisionModeEnabled"
    static let labDeepAssociationModeEnabled = "labDeepAssociationModeEnabled"
    static let labLowConsumptionModeEnabled = "labLowConsumptionModeEnabled"
    static let labRecordOutputLanguage = "labRecordOutputLanguage"
}
