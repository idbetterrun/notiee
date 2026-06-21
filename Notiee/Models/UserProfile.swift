import Foundation

enum LoginMethod: String, Codable, Sendable {
    case local
    case tomago
}

struct UserProfile: Codable, Equatable, Sendable {
    var displayName: String
    var loginMethod: LoginMethod
    var avatarRelativePath: String?
}
