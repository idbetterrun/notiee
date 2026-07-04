import Foundation
import UIKit

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var profile: UserProfile?

    private let userDefaults: UserDefaults
    private let avatarDirectory: URL
    private let profileKey = "notiee_user_profile"

    static let live = AccountStore()

    init(userDefaults: UserDefaults = .standard, avatarDirectory: URL = AccountStore.defaultAvatarDirectory) {
        self.userDefaults = userDefaults
        self.avatarDirectory = avatarDirectory
        load()
    }

    nonisolated static var defaultAvatarDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Notiee/avatar", isDirectory: true)
    }

    var isLoggedIn: Bool { profile != nil }

    func localLogin(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile = UserProfile(displayName: trimmed, loginMethod: .local, avatarRelativePath: profile?.avatarRelativePath, appleUserID: nil)
        save()
    }

    /// Sign in with Apple. `name` is only supplied by Apple on the very first
    /// authorization for a given Apple ID, so we fall back to any existing name
    /// (re-login) and finally a generic label.
    ///
    /// `backendUserID`/`email` are supplied by the Notiee (free) version after the
    /// backend token exchange; both default to `nil` for Notiee+ (BYOK, no
    /// backend account). Like `name`, they fall back to the stored value so a
    /// re-login — where Apple omits the email — doesn't wipe the first-login one.
    func appleLogin(userID: String, name: String?, backendUserID: String? = nil, email: String? = nil) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = (trimmed?.isEmpty == false ? trimmed : nil)
            ?? profile?.displayName
            ?? String(localized: "Apple 用户")
        profile = UserProfile(
            displayName: resolved,
            loginMethod: .apple,
            avatarRelativePath: profile?.avatarRelativePath,
            appleUserID: userID,
            backendUserID: backendUserID ?? profile?.backendUserID,
            email: email ?? profile?.email
        )
        save()
    }

    func updateName(_ name: String) {
        guard var p = profile else { return }
        p.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile = p
        save()
    }

    func setAvatar(_ image: UIImage) {
        guard var p = profile else { return }
        try? FileManager.default.createDirectory(at: avatarDirectory, withIntermediateDirectories: true)
        let resized = AccountStore.resize(image, maxDimension: 256)
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return }
        let fileName = "\(UUID().uuidString).jpg"
        let url = avatarDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: [.atomic])
        } catch { return }
        if let old = p.avatarRelativePath {
            try? FileManager.default.removeItem(at: avatarDirectory.appendingPathComponent(old))
        }
        p.avatarRelativePath = fileName
        profile = p
        save()
    }

    var avatarImage: UIImage? {
        guard let path = profile?.avatarRelativePath else { return nil }
        return UIImage(contentsOfFile: avatarDirectory.appendingPathComponent(path).path)
    }

    func logout() {
        if let old = profile?.avatarRelativePath {
            try? FileManager.default.removeItem(at: avatarDirectory.appendingPathComponent(old))
        }
        profile = nil
        userDefaults.removeObject(forKey: profileKey)
    }

    static func greeting(at date: Date = Date(), calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 0..<5: return String(localized: "凌晨好")
        case 5..<8: return String(localized: "早上好")
        case 8..<11: return String(localized: "上午好")
        case 11..<13: return String(localized: "中午好")
        case 13..<17: return String(localized: "下午好")
        case 17..<23: return String(localized: "晚上好")
        default: return String(localized: "深夜好")
        }
    }

    private func load() {
        guard let data = userDefaults.data(forKey: profileKey),
              let p = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            profile = nil
            return
        }
        profile = p
    }

    private func save() {
        guard let p = profile, let data = try? JSONEncoder().encode(p) else { return }
        userDefaults.set(data, forKey: profileKey)
    }

    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
