import SwiftUI

struct WhatsNewContainerView: View {
    let onDismiss: () -> Void

    private let highlights = [
        WhatsNewHighlight(
            title: "加密拍记 + 隐私锁",
            subtitle: "单条拍记可一键加密，内容以 AES-GCM 本地加密存储；开启隐私锁后用 Face ID 或密码解锁，加密拍记不会出现在导出、同步、搜索与索引中。",
            systemImage: "lock.shield.fill",
            tint: .blue
        ),
        WhatsNewHighlight(
            title: "多语言输出",
            subtitle: "可在「实验室」为拍记设定输出语言（自动跟随或指定），AI 整理会按你选的语言生成标题、摘要与待办。",
            systemImage: "character.bubble.fill",
            tint: .teal
        ),
        WhatsNewHighlight(
            title: "自定义模型",
            subtitle: "在设置中新增的自定义模型现已能正确出现在文本与视觉模型选择器里，按需为不同任务挑选模型。",
            systemImage: "cpu.fill",
            tint: .orange
        ),
        WhatsNewHighlight(
            title: "焕新的开屏与引导",
            subtitle: "开屏品牌画面加入平滑的淡入过渡，隐私协议页也重新设计，首次启动的观感更顺、更清晰。",
            systemImage: "sparkles",
            tint: .pink
        ),
        WhatsNewHighlight(
            title: "稳定性与体验优化",
            subtitle: "对加密拍记执行滑动删除时会先要求验证身份，避免误删；并修复多处细节问题，让整体使用更稳。",
            systemImage: "checkmark.seal.fill",
            tint: .green
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
                Text("\(AppBranding.appName) 更新了")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("这一版更注重隐私与掌控：加密拍记、Face ID 隐私锁、多语言输出与自定义模型一次到位，开屏与引导也焕然一新。")
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

                Text("更私密，也更懂你")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("加密拍记 · 隐私锁 · 多语言")
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
