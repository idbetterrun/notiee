import SwiftUI
import WebKit

/// 法律条款（用户协议 / 隐私政策）本地化文件解析。
/// 语言规则：
/// - App 语言简体中文 → zh-Hans
/// - App 语言 English → en
/// - App 语言繁体中文：设备地区为台湾 → zh-Hant-TW，否则（港澳等）→ zh-Hant-HK
/// - 跟随系统时按系统语言/脚本/地区推断，最终回退 zh-Hans。
enum LegalDocument {
    /// base 为 "UserAgreement" 或 "PrivacyPolicy"。
    static func bundleURL(base: String) -> URL? {
        let suffix = localeSuffix()
        if let url = Bundle.main.url(forResource: "\(base)_\(suffix)", withExtension: "html") {
            return url
        }
        // 缺失语言回退到简体中文。
        if suffix != "zh-Hans",
           let fallback = Bundle.main.url(forResource: "\(base)_zh-Hans", withExtension: "html") {
            return fallback
        }
        return nil
    }

    static func localeSuffix() -> String {
        let lang = UserDefaults.standard.string(forKey: UDK.language) ?? "system"
        switch lang {
        case "zh-Hans": return "zh-Hans"
        case "en": return "en"
        case "zh-Hant":
            return Locale.current.region?.identifier == "TW" ? "zh-Hant-TW" : "zh-Hant-HK"
        default:
            let current = Locale.current
            let region = current.region?.identifier ?? ""
            let langCode = current.language.languageCode?.identifier ?? ""
            let script = current.language.script?.identifier ?? ""
            if langCode == "zh", script == "Hant" {
                return region == "TW" ? "zh-Hant-TW" : "zh-Hant-HK"
            }
            if langCode == "zh" { return "zh-Hans" }
            if langCode == "en" { return "en" }
            return "zh-Hans"
        }
    }
}

/// 渲染打包在 App 内的本地法律条款 HTML（用户协议 / 隐私政策）。
/// 取代旧的 PDF 展示，支持深浅色与系统字号。
struct LegalHTMLView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}
