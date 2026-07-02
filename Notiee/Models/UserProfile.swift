import Foundation

enum LoginMethod: String, Codable, Sendable {
    case local
    case tomago  // legacy — kept so previously stored profiles still decode
    case apple
}

struct UserProfile: Codable, Equatable, Sendable {
    var displayName: String
    var loginMethod: LoginMethod
    var avatarRelativePath: String?
    /// Stable Sign in with Apple user identifier. Optional so older stored
    /// profiles (which predate this field) continue to decode as `nil`.
    var appleUserID: String?
}
