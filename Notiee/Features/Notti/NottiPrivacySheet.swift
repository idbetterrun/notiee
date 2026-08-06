import SwiftUI

struct NottiPrivacySheet: View {
    let onAgree: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            // Icon
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.361, green: 0.682, blue: 0.980),
                            Color(red: 0.325, green: 0.980, blue: 0.671)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.top, 40)

            // Title
            Text(String(localized: "Notti · 你的知识助手"))
                .font(.title2.weight(.bold))

            // Privacy notice
            VStack(alignment: .leading, spacing: 16) {
                privacyItem(
                    icon: "lock.shield",
                    color: Color(red: 0.325, green: 0.980, blue: 0.671),
                    title: String(localized: "记忆在本地加密"),
                    detail: String(localized: "Notti 的记忆库和向量使用设备密钥加密，只保存在本机，不同步到 iCloud。")
                )

                privacyItem(
                    icon: "arrow.triangle.branch",
                    color: Color(red: 0.361, green: 0.682, blue: 0.980),
                    title: String(localized: "只发必要内容"),
                    detail: String(localized: "生成回答或提取记忆时，仅把当前消息、已确认的工具结果和检索命中的少量内容临时发送给所选 AI 模型。")
                )

                privacyItem(
                    icon: "hand.raised",
                    color: .orange,
                    title: String(localized: "敏感信息需确认"),
                    detail: String(localized: "健康、精确地址、联系方式、财务和身份信息默认不会生效，需由你明确要求或确认。")
                )

                privacyItem(
                    icon: "globe",
                    color: Color(red: 0.6, green: 0.4, blue: 0.9),
                    title: String(localized: "联网读取需授权"),
                    detail: String(localized: "仅在 Agent 模式下、且你提供链接时，Notti 才会访问对应网页，相关请求会发往该第三方站点。")
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Agree button
            Button(action: onAgree) {
                Text(String(localized: "了解，开始使用"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(red: 0.361, green: 0.682, blue: 0.980))
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func privacyItem(
        icon: String,
        color: Color,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NottiPrivacySheet(onAgree: {})
}
