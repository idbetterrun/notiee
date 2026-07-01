import SwiftUI

struct WelcomeView: View {
    let onDismiss: () -> Void

    private let features = [
        WelcomeFeature(
            title: "极速拍记",
            subtitle: "打开相机就能记录课堂、会议和现场灵感。",
            systemImage: "camera.viewfinder",
            tint: .blue
        ),
        WelcomeFeature(
            title: "AI 整理",
            subtitle: "自动识别图片文字，生成标题、摘要和待办。",
            systemImage: "sparkles",
            tint: .cyan
        ),
        WelcomeFeature(
            title: "日程归档",
            subtitle: "按课程、会议、文件夹与关键词找回每一次拍记。",
            systemImage: "folder.badge.gearshape",
            tint: .teal
        )
    ]

    var body: some View {
        ZStack {
            WelcomeBackground()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    CaptureJourneyPreview()
                    featureList
                }
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 120)
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomAction
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                NotieeLogoMark(size: 72, cornerRadius: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text("欢迎使用")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Notiee")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("把每一张板书，变成可搜索的知识流")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Notiee 会把拍下来的课堂、会议与灵感自动整理进对应场景，让记录不用再堆成一团。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var featureList: some View {
        VStack(spacing: 12) {
            ForEach(features) { feature in
                WelcomeFeatureRow(feature: feature)
            }
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 0) {
            Button(action: onDismiss) {
                HStack(spacing: 8) {
                    Text("开始使用")
                        .font(.headline)

                    Image(systemName: "arrow.right")
                        .font(.headline.weight(.semibold))
                }
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
}

struct NotieeLogoMark: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    private var logoName: String {
        #if NOTIEE_PLUS
        "LogoNotieePlus"
        #else
        "Notiee-iOS"
        #endif
    }

    var body: some View {
        Group {
            if let logo = UIImage(named: logoName) {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.blue.gradient)
                    .overlay {
                        Text("N")
                            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
        .accessibilityHidden(true)
    }
}

private struct WelcomeBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemGroupedBackground),
                Color.blue.opacity(0.08),
                Color(uiColor: .systemGroupedBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct CaptureJourneyPreview: View {
    private let steps = [
        JourneyStep(title: "拍下", detail: "课堂板书", systemImage: "camera.fill", tint: Color.blue),
        JourneyStep(title: "提炼", detail: "摘要待办", systemImage: "wand.and.stars", tint: Color.cyan),
        JourneyStep(title: "归档", detail: "日程文件夹", systemImage: "tray.full.fill", tint: Color.teal)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("今日拍记流")
                    .font(.headline)

                Spacer()

                Text("自动整理")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12), in: Capsule())
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(steps) { step in
                    VStack(spacing: 9) {
                        Image(systemName: step.systemImage)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(step.tint)
                            .frame(width: 44, height: 44)
                            .background(step.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(spacing: 2) {
                            Text(step.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(step.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        }
    }
}

private struct WelcomeFeatureRow: View {
    let feature: WelcomeFeature

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: feature.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(feature.tint)
                .frame(width: 38, height: 38)
                .background(feature.tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(feature.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct WelcomeFeature: Identifiable {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var id: String { title }
}

private struct JourneyStep: Identifiable {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color

    var id: String { title }
}

#Preview {
    WelcomeView(onDismiss: {})
}
