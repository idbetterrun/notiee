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
                        ScrollView {
                            Text("用户协议内容 (在此处放置完整的用户协议)")
                                .padding()
                        }
                        .navigationTitle("用户协议")
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        ActionRow(title: "用户协议")
                    }
                    Divider().padding(.leading)
                    NavigationLink {
                        ScrollView {
                            Text("隐私政策内容 (在此处放置完整的隐私政策)")
                                .padding()
                        }
                        .navigationTitle("隐私政策")
                        .navigationBarTitleDisplayMode(.inline)
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
                            .foregroundColor(.blue)
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
                        .foregroundColor(.blue)

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
