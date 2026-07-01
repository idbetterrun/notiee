import Foundation

enum AIProcessingState: String, Equatable, Hashable, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
    case deadLetter
}
