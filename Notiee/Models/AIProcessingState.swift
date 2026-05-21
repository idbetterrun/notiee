import Foundation

enum AIProcessingState: String, Equatable, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
}
