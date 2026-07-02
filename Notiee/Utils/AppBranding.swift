import Foundation

/// Centralized app name so Notiee/Notiee+-specific copy doesn't drift.
enum AppBranding {
    static let appName: String = {
        #if NOTIEE_PLUS
        "Notiee+"
        #else
        "Notiee"
        #endif
    }()
}
