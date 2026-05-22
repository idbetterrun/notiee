import Foundation

struct AIProcessingResult: Sendable {
    let title: String
    let ocrText: String
    let summary: String
    let detailedContent: String
    let todos: [String]
    let modelsUsed: [String]?
    let tokenUsage: Int
}

protocol AIProcessingService: Sendable {
    func process(imagePaths: [String], eventTitle: String?) async throws -> AIProcessingResult
}
