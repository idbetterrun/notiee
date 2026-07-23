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

    // Single boolean drives the whole reveal. We deliberately animate via the
    // declarative `.animation(_:value:)` modifier rather than an imperative
    // `withAnimation` block: the dismissal is triggered from inside a `.task`
    // after `await Task.sleep`, and `withAnimation` fired from that async
    // continuation would frequently NOT animate (the transaction wasn't picked
    // up), producing the hard cut. `.animation(_:value:)` animates reliably
    // whenever the bound value flips, regardless of where the mutation happened.
    @State private var splashDismissed = false

    private let splashRevealDuration: TimeInterval = 0.6

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
                // Content grows in as the splash zooms out, so the reveal reads as
                // one coordinated motion rather than a lid being peeled off.
                .opacity(splashDismissed ? 1 : 0)
                .scaleEffect(splashDismissed ? 1 : 0.92)
                .animation(.easeInOut(duration: splashRevealDuration), value: splashDismissed)

                if appLock.isLocked {
                    AppLockView(lock: appLock)
                        .transition(.opacity)
                        .zIndex(1)
                }

                if isSplashActive {
                    SplashView()
                        .opacity(splashDismissed ? 0 : 1)
                        .scaleEffect(splashDismissed ? 1.12 : 1)
                        .animation(.easeInOut(duration: splashRevealDuration), value: splashDismissed)
                        .zIndex(2)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: appLock.isLocked)
            .preferredColorScheme(colorScheme)
            .tint(appTint)
            .environment(\.sizeCategory, contentSizeCategory)
            .task {
                // Keep the branded splash up for a minimum, clearly perceptible
                // duration — this used to be 500ms, which on a fast cold launch
                // (small/local dataset) meant the fade could start almost
                // immediately, making the whole thing feel like a flash.
                try? await Task.sleep(nanoseconds: 1_200_000_000)
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
        guard isContentReady, isMinimumHoldElapsed, !splashDismissed else { return }

        // Flip the flag; `.animation(_:value:)` on both layers drives the crossfade.
        splashDismissed = true

        // Drop the splash from the tree only after the crossfade has finished, so
        // the fade actually plays out instead of the view vanishing mid-animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + splashRevealDuration) {
            isSplashActive = false
        }
    }
}

/// Full-screen branded launch cover shown over the app while it warms up on
/// cold launch. Follows light/dark automatically and picks the brand image per
/// target (Notiee vs. Notiee+).
private struct SplashView: View {
    // Very subtle breathing scale so the hold doesn't read as a dead/frozen
    // frame while we wait out the minimum display duration.
    @State private var isBreathing = false

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
                .scaleEffect(isBreathing ? 1.015 : 1.0)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        try? SparkConversationRepository.live.clearDraft()
        #if !NOTIEE_PLUS
        // First launch after a (re)install: drop any Keychain session the deleted
        // install left behind, so the app doesn't appear logged-in with stale
        // quota. Must run before anything reads the token below.
        AuthService.shared.purgeStaleSessionOnFreshInstall()
        #endif
        #if !NOTIEE_PLUS && DEBUG
        // Phase 0 convenience: swap a stable fake identity token for a real
        // backend JWT so the AI pipeline is testable before Sign in with Apple is
        // exercised. No-op once a real session (Phase 1) exists. Requires the
        // backend running with ALLOW_FAKE_APPLE=1.
        Task { try? await AuthService.shared.devLoginIfNeeded() }
        #endif
        #if canImport(FirebaseCore)
        FirebaseApp.configure()
        #endif
        UNUserNotificationCenter.current().delegate = self
        AIBackgroundTaskScheduler.shared.register {
            await NotieeProcessingRuntime.shared.runPendingProcessing()
        }
        Task { @MainActor in
            await NotieeProcessingRuntime.shared.runPendingProcessing()
        }
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
