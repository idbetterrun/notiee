import SwiftUI

struct AboutNotieeView: View {
    /// 开发者署名三态，点击循环（彩蛋）。默认 idbetterrun。
    private let developerNames = ["idbetterrun", "woxiantao", "我先逃"]
    @State private var developerIndex = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Logo & Name
                VStack(spacing: 12) {
                    NotieeLogoMark(size: 100, cornerRadius: 22)

                    Text(AppBranding.appName)
                        .font(.title.weight(.bold))
                }
                .padding(.top, 40)

                // Info Section
                VStack(spacing: 0) {
                    InfoRow(title: "版本号", value: versionText)
                    Divider().padding(.leading)
                    Button {
                        developerIndex = (developerIndex + 1) % developerNames.count
                    } label: {
                        InfoRow(title: "开发者", value: developerNames[developerIndex])
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading)
                    InfoRow(title: "联系邮箱", value: "woxiantao@icloud.com")
                    Divider().padding(.leading)
                    Link(destination: URL(string: "https://tanqinghua.asia")!) {
                        InfoRow(title: "开发者网页", value: "tanqinghua.asia", showsLinkChevron: true)
                    }
                    .buttonStyle(.plain)
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Links Section
                VStack(spacing: 0) {
                    NavigationLink {
                        legalHTMLView(base: "UserAgreement", title: "用户协议")
                    } label: {
                        ActionRow(title: "用户协议")
                    }
                    Divider().padding(.leading)
                    NavigationLink {
                        legalHTMLView(base: "PrivacyPolicy", title: "隐私政策")
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
        .navigationTitle("关于 \(AppBranding.appName)")
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

    private func legalHTMLView(base: String, title: String) -> some View {
        Group {
            if let url = LegalDocument.bundleURL(base: base) {
                LegalHTMLView(url: url)
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
    var showsLinkChevron: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .foregroundColor(showsLinkChevron ? NotieeColors.themed(.blue) : .secondary)
            if showsLinkChevron {
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .contentShape(Rectangle())
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
