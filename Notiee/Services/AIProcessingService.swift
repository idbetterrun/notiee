import Foundation

struct AIProcessingResult: Sendable {
    let title: String
    let ocrText: String
    let summary: String
    let todos: [String]
}

protocol AIProcessingService: Sendable {
    func process(imagePath: String, eventTitle: String?) async throws -> AIProcessingResult
}
