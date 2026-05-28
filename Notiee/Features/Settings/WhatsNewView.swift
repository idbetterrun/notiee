import SwiftUI

struct WhatsNewContainerView: View {
    let onDismiss: () -> Void

    private let highlights = [
        WhatsNewHighlight(
            title: "全新登录页",
            subtitle: "简洁的单按钮登录，协议未勾选时提示会左右抖动提醒你。支持浅色/深色模式。",
            systemImage: "person.fill.checkmark",
            tint: .green
        ),
        WhatsNewHighlight(
            title: "主题色切换",
            subtitle: "设置 > 外观中可选择 Notiee 翠绿配色，菜单图标、按钮统一跟随主题色变化。",
            systemImage: "paintpalette.fill",
            tint: .green
        ),
        WhatsNewHighlight(
            title: "相机启动更流畅",
            subtitle: "进入拍记页先展示旋转环加载动画，相机就绪后平滑切入预览，不再有卡顿感。",
            systemImage: "camera.macro",
            tint: .blue
        ),
        WhatsNewHighlight(
            title: "文字框选与复制",
            subtitle: "记录详情页的 AI 摘要、详细内容、OCR 原文均支持长按选中文字，弹出复制/分享菜单。",
            systemImage: "selection.pin.in.out",
            tint: .orange
        ),
        WhatsNewHighlight(
            title: "Token 消耗追踪",
            subtitle: "回顾页展示 Token 消耗 Top 5 记录排行，删除记录自动累计消耗量。详情页右上角可查看单条 Token 数。",
            systemImage: "chart.pie.fill",
            tint: .purple
        ),
        WhatsNewHighlight(
            title: "日程路径去重",
            subtitle: "拍记页和记录页的日程路径列表自动过滤节假日，相同标题只显示一次，不再重复堆叠。",
            systemImage: "calendar.badge.clock",
            tint: .indigo
        ),
        WhatsNewHighlight(
            title: "学生模式 & 深度联想",
            subtitle: "大学/中学场景预设可标记课程日历并置顶显示。记录详情页自动推荐相关历史笔记。",
            systemImage: "brain.head.profile.fill",
            tint: .pink
        ),
        WhatsNewHighlight(
            title: "Lottie 动效框架",
            subtitle: "引入 Airbnb Lottie 引擎，后续版本将陆续添加精美动画，敬请期待。",
            systemImage: "sparkles",
            tint: .yellow
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

                Text("这次重点打磨了登录体验、主题配色、文字交互和 Token 追踪。")
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

                Text("更好看，更好用")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("从拍到查全链路体验优化。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 52, height: 52)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
