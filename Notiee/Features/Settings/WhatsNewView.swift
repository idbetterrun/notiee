import SwiftUI

struct WhatsNewContainerView: View {
    let onDismiss: () -> Void

    private let highlights = [
        WhatsNewHighlight(
            title: "Spark Agent 全面增强",
            subtitle: "Agent 模式新增日程修改、日期查询、网页抓取等工具，还能切换模型与思考强度，生成中可随时终止回复。",
            systemImage: "sparkles",
            tint: .orange
        ),
        WhatsNewHighlight(
            title: "语义检索 + 深度联想",
            subtitle: "拍记搜索升级为语义理解，不再只靠关键词；详情页底部按内容相关度智能推荐相关历史笔记。默认全程在设备本地计算，不外传。",
            systemImage: "brain.head.profile.fill",
            tint: .pink
        ),
        WhatsNewHighlight(
            title: "全量待办管理",
            subtitle: "全新待办页面，按截止日分桶（逾期 / 今天 / 明天 / 本周 / 更晚）；待办与截止日期现已稳定保存，重启不丢。",
            systemImage: "checklist",
            tint: .green
        ),
        WhatsNewHighlight(
            title: "本地账户",
            subtitle: "设置昵称与头像，拥有专属身份标识。所有资料仅存本机，不上传任何服务器。",
            systemImage: "person.crop.circle.fill",
            tint: .blue
        ),
        WhatsNewHighlight(
            title: "纯文本记录",
            subtitle: "不止拍照，现在也能直接新建文字笔记，随手记录想法。",
            systemImage: "square.and.pencil",
            tint: .teal
        ),
        WhatsNewHighlight(
            title: "记录详情焕新",
            subtitle: "详情页按来源智能呈现内容，去除冗余区块；Spark 生成的记录带真摘要不再与正文重复；Markdown 渲染开关移至「设置 → 外观」。",
            systemImage: "doc.text.image",
            tint: .indigo
        ),
        WhatsNewHighlight(
            title: "日程颜色标签",
            subtitle: "给日程打上彩色标签（工作 / 课程 / 临时等），现已稳定保存，重启后颜色不再丢失。",
            systemImage: "tag.fill",
            tint: .purple
        ),
        WhatsNewHighlight(
            title: "备份与稳定性",
            subtitle: "单个 .tmn 文件导入移至「备份与恢复」；修复多项数据持久化问题，让你的记录更安心。",
            systemImage: "externaldrive.fill.badge.checkmark",
            tint: .gray
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

                Text("Spark 更聪明了，待办与记录更稳更全：语义检索、深度联想、全量待办、本地账户与纯文本记录一次到位。")
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

                Text("更聪明，也更稳了")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("语义检索 · 深度联想 · 全量待办")
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
