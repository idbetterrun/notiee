import SwiftUI
import UserNotifications
import ActivityKit

@main
struct NotieeApp: App {
    @AppStorage("notiee.theme") private var theme: String = "system"
    @AppStorage("notiee.fontSize") private var fontSize: String = "medium"
    @AppStorage("notiee.language") private var language: String = "system"
    
    @AppStorage("hasAgreedToPrivacy") private var hasAgreedToPrivacy = false
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false
    @AppStorage("hasSeenPermissions") private var hasSeenPermissions = false
    @AppStorage("lastAppVersion") private var lastAppVersion = ""
    
    private let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            if !hasAgreedToPrivacy {
                PrivacyAgreementView(hasAgreed: $hasAgreedToPrivacy)
                    .preferredColorScheme(colorScheme)
            } else if !hasSeenWelcome {
                WelcomeView {
                    // Trigger permissions before continuing
                    SystemPermissionManager.shared.requestAllPermissions {
                        hasSeenWelcome = true
                    }
                }
                .preferredColorScheme(colorScheme)
            } else if lastAppVersion != "" && lastAppVersion != currentAppVersion {
                WhatsNewContainerView {
                    lastAppVersion = currentAppVersion
                }
                .preferredColorScheme(colorScheme)
            } else {
                RootTabView()
                    .preferredColorScheme(colorScheme)
                    .environment(\.sizeCategory, contentSizeCategory)
                    .onAppear {
                        if lastAppVersion == "" {
                            lastAppVersion = currentAppVersion
                        }
                    }
            }
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
    
    private var locale: Locale {
        switch language {
        case "zh-Hans": return Locale(identifier: "zh-Hans")
        case "zh-Hant": return Locale(identifier: "zh-Hant")
        case "en": return Locale(identifier: "en")
        default: return Locale.current
        }
    }
    
    private var contentSizeCategory: ContentSizeCategory {
        switch fontSize {
        case "small": return .small
        case "medium": return .large
        case "large": return .extraLarge
        case "extraLarge": return .accessibilityExtraLarge
        default: return .large
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        if LiveActivityManager.isEndNotification(identifier) {
            Task { @MainActor in
                LiveActivityManager.shared.endActivity()
            }
        }
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let identifier = notification.request.identifier
        if LiveActivityManager.isEndNotification(identifier) {
            Task { @MainActor in
                LiveActivityManager.shared.endActivity()
            }
            completionHandler([])
        } else {
            completionHandler([.banner, .sound, .badge])
        }
    }
}
