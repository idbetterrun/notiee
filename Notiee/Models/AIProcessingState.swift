import Foundation

enum AIProcessingState: String, Equatable, Hashable, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
    case deadLetter
}

enum ProcessingNotificationState: String, Equatable, Hashable, Codable, Sendable {
    case none
    case requested
    case delivered
}
