import SwiftUI
import Charts


// MARK: - OpenSourceAcknowledgmentsView
struct OpenSourceAcknowledgmentsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Notiee 感谢开源社区的力量，正是这些优秀的项目让我们的应用变得更好！")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                
                VStack(alignment: .leading, spacing: 16) {
                    openSourceItem(name: "SwiftUI", url: "https://developer.apple.com/xcode/swiftui/", description: "Notiee 全面采用了 SwiftUI 构建现代化、响应式的用户界面，感谢苹果提供的强大底层框架。")
                    openSourceItem(name: "Swift Charts", url: "https://developer.apple.com/documentation/charts", description: "Notiee 的数据回顾仪表盘由 Swift Charts 提供图表渲染，直观展示您的 Token 消耗。")
                    openSourceItem(name: "swift-markdown-ui", url: "https://github.com/gonzalezreal/swift-markdown-ui", description: "Notiee 使用该库在详情页提供了优雅的 Markdown 渲染支持。")
                    openSourceItem(name: "ZIPFoundation", url: "https://github.com/weichsel/ZIPFoundation", description: "Notiee 使用该库提供了可靠的压缩和解压能力，用于处理 .tmn 文件的导入与导出。")
                    openSourceItem(name: "OnboardingKit", url: "https://github.com/danielsaidi/OnboardingKit", description: "Notiee 使用该库构建了精美的欢迎与首次引导页面。")
                    openSourceItem(name: "WhatsNewKit", url: "https://github.com/SvenTiigi/WhatsNewKit", description: "Notiee 使用该库来展示更新日志和新版本特性。")
                    openSourceItem(name: "Vision Framework", url: "https://developer.apple.com/documentation/vision", description: "原生提供了强大的 OCR 视觉框架，为 Notiee 本地初步的文字提取提供了技术支持。")
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("开源声明")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func openSourceItem(name: String, url: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(name, destination: URL(string: url)!)
                .font(.headline)
                .foregroundColor(.blue)
            
            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider()
        }
    }
}
