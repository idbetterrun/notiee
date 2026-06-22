import SwiftUI

struct SparkPrivacySheet: View {
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
            Text(String(localized: "Spark - 你的知识 AI"))
                .font(.title2.weight(.bold))

            // Privacy notice
            VStack(alignment: .leading, spacing: 16) {
                privacyItem(
                    icon: "lock.shield",
                    color: Color(red: 0.325, green: 0.980, blue: 0.671),
                    title: String(localized: "本地检索"),
                    detail: String(localized: "所有拍记内容的检索和匹配均在设备本地完成，不会上传到云端。")
                )

                privacyItem(
                    icon: "arrow.triangle.branch",
                    color: Color(red: 0.361, green: 0.682, blue: 0.980),
                    title: String(localized: "最小化上传"),
                    detail: String(localized: "仅你的问题和检索到的记录片段会发送给 AI 模型以生成回答。")
                )

                privacyItem(
                    icon: "hand.raised",
                    color: .orange,
                    title: String(localized: "不用于训练"),
                    detail: String(localized: "你的拍记内容不会用于任何模型训练或分享给第三方。")
                )

                privacyItem(
                    icon: "globe",
                    color: Color(red: 0.6, green: 0.4, blue: 0.9),
                    title: String(localized: "网页抓取（Agent 模式）"),
                    detail: String(localized: "开启 Agent 模式时，若你提供网页链接，Spark 可能会访问该网页以读取内容，相关请求会发送到对应的第三方网站。")
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
    SparkPrivacySheet(onAgree: {})
}
