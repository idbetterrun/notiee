import SwiftUI

struct AboutNotieeView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Logo & Name
                VStack(spacing: 12) {
                    NotieeLogoMark(size: 100, cornerRadius: 22)

                    Text("Notiee")
                        .font(.title.weight(.bold))
                }
                .padding(.top, 40)

                // Info Section
                VStack(spacing: 0) {
                    InfoRow(title: "版本号", value: versionText)
                    Divider().padding(.leading)
                    InfoRow(title: "开发者", value: "douyin@idbetterrun")
                    Divider().padding(.leading)
                    InfoRow(title: "联系邮箱", value: "woxiantao@icloud.com")
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Links Section
                VStack(spacing: 0) {
                    NavigationLink {
                        legalPDFView(base: "UserAgreement", title: "用户协议")
                    } label: {
                        ActionRow(title: "用户协议")
                    }
                    Divider().padding(.leading)
                    NavigationLink {
                        legalPDFView(base: "PrivacyPolicy", title: "隐私政策")
                    } label: {
                        ActionRow(title: "隐私政策")
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // TomaNotes Link
                Link(destination: URL(string: "https://github.com/idbetterrun/TomaNotes")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "desktopcomputer")
                            .foregroundColor(NotieeColors.themed(.blue))
                            .frame(width: 24)

                        Text("您在用 macOS 吗？来试试 TomaNotes 吧！")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                    }
                    .padding()
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal)

                Spacer(minLength: 40)

                // Footer
                VStack(spacing: 8) {
                    Link("ICP备案号: xxx", destination: URL(string: "https://beian.miit.gov.cn/#/home")!)
                        .font(.caption)
                        .foregroundColor(NotieeColors.themed(.blue))

                    Text("Copyright © 2026 Tan Qinghua All Rights Reserved.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 20)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("关于 Notiee")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        guard let build, !build.isEmpty, build != version else {
            return version
        }

        return "\(version) (\(build))"
    }

    private var legalLocaleSuffix: String {
        let lang = UserDefaults.standard.string(forKey: UDK.language) ?? "system"
        switch lang {
        case "zh-Hans": return "zh-Hans"
        case "en": return "en"
        case "zh-Hant":
            let region = Locale.current.region?.identifier ?? ""
            if region == "TW" { return "zh-Hant-TW" }
            return "zh-Hant-HK"
        default:
            let current = Locale.current
            let region = current.region?.identifier ?? ""
            let langCode = current.language.languageCode?.identifier ?? ""
            let script = current.language.script?.identifier ?? ""

            if langCode == "zh", script == "Hant" {
                if region == "TW" { return "zh-Hant-TW" }
                return "zh-Hant-HK"
            }
            if langCode == "zh" { return "zh-Hans" }
            if langCode == "en" { return "en" }
            return "zh-Hans"
        }
    }

    private func legalPDFURL(base: String) -> URL? {
        let suffix = legalLocaleSuffix
        if let url = Bundle.main.url(forResource: "\(base)_\(suffix)", withExtension: "pdf") {
            return url
        }
        if suffix != "zh-Hans",
           let fallback = Bundle.main.url(forResource: "\(base)_zh-Hans", withExtension: "pdf") {
            return fallback
        }
        return nil
    }

    private func legalPDFView(base: String, title: String) -> some View {
        Group {
            if let url = legalPDFURL(base: base) {
                PDFPreviewView(url: url)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ScrollView {
                    Text("无法加载\(title)")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

private struct ActionRow: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .font(.footnote)
        }
        .padding()
    }
}
