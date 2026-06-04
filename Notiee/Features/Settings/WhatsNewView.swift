import SwiftUI

struct WhatsNewContainerView: View {
    let onDismiss: () -> Void

    private let highlights = [
        WhatsNewHighlight(
            title: "Spark AI 伴侣",
            subtitle: "全新第四标签页，智能 AI 助手帮你回顾笔记、回答问题，支持对话历史与自动记忆。",
            systemImage: "sparkles",
            tint: .orange
        ),
        WhatsNewHighlight(
            title: "Spark 风格自定义",
            subtitle: "6 种预设聊天风格（温柔知心、犀利毒舌等），还支持自定义风格指令，打造专属 AI 伴侣。",
            systemImage: "theatermasks",
            tint: .purple
        ),
        WhatsNewHighlight(
            title: "智能记忆系统",
            subtitle: "Spark 会自动记住你的名字、偏好和习惯，下次聊天时自然提起，越聊越懂你。",
            systemImage: "brain.head.profile.fill",
            tint: .pink
        ),
        WhatsNewHighlight(
            title: "Spark Token 追踪",
            subtitle: "回顾页新增 Spark 耗费Token估计，独立统计 AI 对话消耗，与拍记 Token 分开显示。",
            systemImage: "chart.pie.fill",
            tint: .blue
        ),
        WhatsNewHighlight(
            title: "多语言全面适配",
            subtitle: "完善繁体中文与 English 的全界面翻译，覆盖 Spark、设置、回顾等全部页面，告别机翻感。",
            systemImage: "globe",
            tint: .indigo
        ),
        WhatsNewHighlight(
            title: "架构与性能优化",
            subtitle: "管理架构重组、设置页拆分、Key 集中化，代码更规范，页面加载速度大幅提升。",
            systemImage: "gearshape.2.fill",
            tint: .gray
        ),
        WhatsNewHighlight(
            title: "AI Pipeline 修复",
            subtitle: "移除无限重试循环，引入指数退避机制，网络异常时快速返回错误不再卡死。",
            systemImage: "arrow.triangle.merge",
            tint: .green
        ),
        WhatsNewHighlight(
            title: "日程匹配增强",
            subtitle: "修复系统日历事件 ID 重启后变化导致丢失关联的问题，日程追踪更稳定。",
            systemImage: "calendar.badge.clock",
            tint: .teal
        )
    ]

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    updateSummaryCard
                    highlightList
                }
                .padding(.horizontal, 24)
                .padding(.top, 42)
                .padding(.bottom, 118)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomAction
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            NotieeLogoMark(size: 68, cornerRadius: 17)

            VStack(alignment: .leading, spacing: 8) {
                Text("Notiee 更新了")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("这次重磅推出 Spark AI 伴侣，并完成了全面的多语言适配与性能优化。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var updateSummaryCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(versionText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)

                Text("你的 AI 伴侣来了")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Spark 正式登场，多语言全面适配。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 52, height: 52)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var highlightList: some View {
        VStack(spacing: 12) {
            ForEach(highlights) { highlight in
                WhatsNewHighlightRow(highlight: highlight)
            }
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 0) {
            Button(action: onDismiss) {
                Text("继续")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(NotieeColors.primary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .background(.regularMaterial)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "版本 \(version)"
    }
}

private struct WhatsNewHighlightRow: View {
    let highlight: WhatsNewHighlight

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: highlight.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(highlight.tint)
                .frame(width: 42, height: 42)
                .background(highlight.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(highlight.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(highlight.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WhatsNewHighlight: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var id: String { title }
}

#Preview {
    WhatsNewContainerView(onDismiss: {})
}
