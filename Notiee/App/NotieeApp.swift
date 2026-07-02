import SwiftUI
import UserNotifications
import ActivityKit
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct NotieeApp: App {
    @AppStorage(UDK.theme) private var theme: String = "system"
    @AppStorage(UDK.fontSize) private var fontSize: String = "medium"
    @AppStorage(UDK.language) private var language: String = "system"
    @AppStorage(UDK.accentColor) private var accentColor: String = "default"

    @AppStorage(UDK.hasAgreedToPrivacy) private var hasAgreedToPrivacy = false
    @AppStorage(UDK.hasSeenWelcome) private var hasSeenWelcome = false
    @AppStorage(UDK.hasSeenPermissions) private var hasSeenPermissions = false
    @AppStorage(UDK.lastAppVersion) private var lastAppVersion = ""

    private let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.5"

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var appLock = AppLockManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var isSplashActive = true
    @State private var isContentReady = false
    @State private var isMinimumHoldElapsed = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if !hasAgreedToPrivacy {
                        PrivacyAgreementView(hasAgreed: $hasAgreedToPrivacy)
                    } else if !hasSeenWelcome {
                        WelcomeView {
                            SystemPermissionManager.shared.requestAllPermissions {
                                hasSeenWelcome = true
                            }
                        }
                    } else if lastAppVersion != "" && lastAppVersion != currentAppVersion {
                        WhatsNewContainerView {
                            lastAppVersion = currentAppVersion
                        }
                    } else {
                        RootTabView()
                            .onAppear {
                                if lastAppVersion == "" {
                                    lastAppVersion = currentAppVersion
                                }
                            }
                    }
                }
                // Fires once the visible branch has finished its (possibly heavy,
                // synchronous) init and laid out — used to gate the splash dismissal
                // so the fade animation never runs while the main thread is still
                // busy loading data, which is what made it look instant/hard-cut.
                .onAppear { isContentReady = true }

                if appLock.isLocked {
                    AppLockView(lock: appLock)
                        .transition(.opacity)
                        .zIndex(1)
                }

                if isSplashActive {
                    SplashView()
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                        .zIndex(2)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: appLock.isLocked)
            .preferredColorScheme(colorScheme)
            .tint(appTint)
            .environment(\.sizeCategory, contentSizeCategory)
            .task {
                // Keep the branded splash up for a minimum, pleasant duration...
                try? await Task.sleep(nanoseconds: 500_000_000)
                isMinimumHoldElapsed = true
                dismissSplashIfReady()
            }
            .onChange(of: isContentReady) { _, _ in
                // ...but never start the fade until the content behind it has
                // actually appeared, so the animation doesn't compete with
                // cold-launch data loading for the main thread.
                dismissSplashIfReady()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appLock.appDidEnterBackground()
            case .active:
                appLock.appWillEnterForeground()
            default:
                break
            }
        }
    }

    private var appTint: Color? {
        accentColor == "notiee" ? NotieeColors.primary : nil
    }

    private var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
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

    private func dismissSplashIfReady() {
        guard isContentReady, isMinimumHoldElapsed, isSplashActive else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            isSplashActive = false
        }
    }
}

/// Full-screen branded launch cover shown over the app while it warms up on
/// cold launch. Follows light/dark automatically and picks the brand image per
/// target (Notiee vs. Notiee+).
private struct SplashView: View {
    private var imageName: String {
        #if NOTIEE_PLUS
        "LaunchNotieePlus"
        #else
        "LaunchNotiee"
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .ignoresSafeArea()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        try? SparkConversationRepository.live.clearDraft()
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif
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
