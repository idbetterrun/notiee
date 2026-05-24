import SwiftUI

struct WhatsNewContainerView: View {
    let onDismiss: () -> Void

    private let highlights = [
        WhatsNewHighlight(
            title: "支持相机控制按键",
            subtitle: "可以把 Notiee 设置为相机控制默认应用，举起手机就开始拍记。",
            systemImage: "camera.macro",
            tint: .blue
        ),
        WhatsNewHighlight(
            title: "记录浏览更清爽",
            subtitle: "卡片、文件夹和列表细节重新整理，归档内容更容易扫读。",
            systemImage: "rectangle.grid.2x2.fill",
            tint: .teal
        ),
        WhatsNewHighlight(
            title: "学生模式增强",
            subtitle: "实验室中开启后，可识别课表并围绕课程组织学习记录。",
            systemImage: "graduationcap.fill",
            tint: .orange
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

                Text("这次主要把拍记入口、记录浏览和学生场景打磨得更顺手。")
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
                    .foregroundStyle(.blue)

                Text("更快开始，更稳归档")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("围绕「拍下、理解、找回」这条主线整理体验。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 52, height: 52)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                    .background(.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
