import SwiftUI
import WebKit

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
