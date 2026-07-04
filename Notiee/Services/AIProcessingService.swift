import Foundation

struct AIProcessingResult: Sendable {
    let title: String
    let ocrText: String
    let summary: String
    let detailedContent: String
    let todos: [String]
    let keyPoints: [String]
    let definitions: [KeyDefinition]
    let modelsUsed: [String]?
    let tokenUsage: Int
}

protocol AIProcessingService: Sendable {
    func process(imagePaths: [String], eventTitle: String?) async throws -> AIProcessingResult
}

/// Single compile-flag gate for which note-processing backend the app uses.
/// Notiee+ (BYOK) keeps the direct-to-provider `RealAIProcessingService`; Notiee
/// (free) routes through the self-hosted backend. Confining the `#if` here keeps
/// injection sites (`NotieeStore`) branch-free — the `AppBranding` philosophy.
enum AIProcessingServiceFactory {
    static func makeDefault() -> any AIProcessingService {
        #if NOTIEE_PLUS
        RealAIProcessingService()
        #else
        BackendAIProcessingService()
        #endif
    }
}
