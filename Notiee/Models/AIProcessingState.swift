import Foundation

enum AIProcessingState: Equatable, Hashable, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
    case deadLetter
}
