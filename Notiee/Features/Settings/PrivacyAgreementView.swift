import SwiftUI

struct PrivacyAgreementView: View {
    @Binding var hasAgreed: Bool

    @State private var legalDoc: LegalDocKind?

    private let points = [
        PrivacyPoint(
            title: "权限用途",
            detail: "相机、相册、麦克风和语音识别，仅用于拍照、录音与文字记录。",
            systemImage: "camera.fill"
        ),
        PrivacyPoint(
            title: "本机存储",
            detail: "所有记录默认保存在你的设备或私人 iCloud，我们不做云端留存。",
            systemImage: "iphone"
        ),
        PrivacyPoint(
            title: "加密传输",
            detail: "使用 AI 时，文本与图片加密发送至你选定的服务商，\(AppBranding.appName) 不截留。",
            systemImage: "lock.fill"
        )
    ]

    var body: some View {
        VStack(spacing: 24) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    ForEach(points) { point in
                        PrivacyPointRow(point: point)
                    }

                    legalLinks
                }
                .padding(.horizontal)
            }

            bottomActions
        }
        .padding(.top, 40)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .sheet(item: $legalDoc) { doc in
            LegalDocumentSheet(kind: doc)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            Text("欢迎使用 \(AppBranding.appName)")
                .font(.title.weight(.bold))

            Text("开始前，先花一分钟了解我们如何处理你的数据。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
        }
    }

    private var legalLinks: some View {
        HStack(spacing: 12) {
            LegalLinkButton(title: "用户协议", systemImage: "doc.text.fill") {
                legalDoc = .userAgreement
            }
            LegalLinkButton(title: "隐私政策", systemImage: "lock.shield.fill") {
                legalDoc = .privacyPolicy
            }
        }
        .padding(.top, 4)
    }

    private var bottomActions: some View {
        VStack(spacing: 14) {
            Button {
                hasAgreed = true
            } label: {
                Text("同意并继续")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                exit(0)
            } label: {
                Text("不同意并退出")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("点击“同意并继续”即表示你已阅读并接受以上条款。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .padding(.horizontal)
        .padding(.bottom, 32)
    }
}

private struct PrivacyPoint: Identifiable {
    let title: String
    let detail: String
    let systemImage: String

    var id: String { title }
}

private struct PrivacyPointRow: View {
    let point: PrivacyPoint

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: point.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(point.title))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(LocalizedStringKey(point.detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LegalLinkButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.footnote)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private enum LegalDocKind: Identifiable {
    case userAgreement
    case privacyPolicy

    var id: String { base }

    /// 对应 LegalDocument.bundleURL(base:) 的资源前缀。
    var base: String {
        switch self {
        case .userAgreement: return "UserAgreement"
        case .privacyPolicy: return "PrivacyPolicy"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .userAgreement: return "用户协议"
        case .privacyPolicy: return "隐私政策"
        }
    }
}

/// 以 sheet 形式展示本地化法律条款 HTML。
private struct LegalDocumentSheet: View {
    let kind: LegalDocKind
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url = LegalDocument.bundleURL(base: kind.base) {
                    LegalHTMLView(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ScrollView {
                        Text("无法加载条款内容")
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PrivacyAgreementView(hasAgreed: .constant(false))
}
