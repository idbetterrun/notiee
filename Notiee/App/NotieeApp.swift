import SwiftUI

@main
struct NotieeApp: App {
    @AppStorage("notiee.theme") private var theme: String = "system"
    @AppStorage("notiee.fontSize") private var fontSize: String = "medium"
    @AppStorage("notiee.language") private var language: String = "system"

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .preferredColorScheme(colorScheme)
                .environment(\.locale, locale)
                .environment(\.sizeCategory, contentSizeCategory)
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
        case "medium": return .large // Native default is `.large` for normal
        case "large": return .extraLarge
        case "extraLarge": return .accessibilityExtraLarge
        default: return .large
        }
    }
}
