import SwiftUI

struct NewUIPreviewRecordCard: View {
    let fixture: NewUIPreviewRecordFixture
    let action: () -> Void

    private var record: NoteRecord { fixture.record }

    var body: some View {
        Button(action: action) {
            Group {
                if record.isEncrypted {
                    encryptedContent
                } else if record.processingState == .pending || record.processingState == .processing {
                    processingContent
                } else {
                    regularContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                Color(uiColor: .secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(NewUIPreviewRecordCardButtonStyle())
        .accessibilityHint("打开记录详情")
    }

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            stateAndTimestamp

            Text(record.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.newUIPreviewPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(Color.newUIPreviewSecondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }

            if !fixture.media.isEmpty {
                NewUIPreviewRecordMediaView(media: fixture.media)
            }

            metadata
        }
    }

    private var encryptedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text("已加密")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.newUIPreviewAccent)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.newUIPreviewAccent)
                .frame(maxWidth: .infinity, minHeight: 62)
                .accessibilityHidden(true)

            Text("受保护的记录")
                .font(.headline.weight(.semibold))
                .foregroundStyle(Color.newUIPreviewPrimary)

            Text("打开详情后验证身份以查看内容")
                .font(.subheadline)
                .foregroundStyle(Color.newUIPreviewSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: 176, alignment: .topLeading)
    }

    private var processingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(processingLabel, systemImage: processingSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.newUIPreviewAccent)

            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 16)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 104, height: 13)
            }
            .accessibilityHidden(true)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(height: 112)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
                .accessibilityHidden(true)
        }
        .frame(height: 205, alignment: .topLeading)
    }

    private var stateAndTimestamp: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Label(stateLabel, systemImage: stateSymbol)
                .foregroundStyle(stateColor)

            Spacer(minLength: 4)

            Text(record.capturedAt.formatted(date: .abbreviated, time: .shortened))
                .foregroundStyle(Color.newUIPreviewSecondary)
                .lineLimit(1)
        }
        .font(.caption2.weight(.medium))
    }

    @ViewBuilder
    private var metadata: some View {
        let values = [fixture.eventName, fixture.folderName].compactMap { $0 }
        if !values.isEmpty {
            HStack(spacing: 5) {
                ForEach(values.prefix(2), id: \.self) { value in
                    Text(value)
                        .font(.caption2)
                        .foregroundStyle(Color.newUIPreviewSecondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var processingLabel: String {
        record.processingState == .pending ? String(localized: "等待整理") : String(localized: "正在整理")
    }

    private var processingSymbol: String {
        record.processingState == .pending ? "clock" : "wand.and.stars"
    }

    private var stateLabel: String {
        switch record.processingState {
        case .completed: return sourceLabel
        case .failed, .deadLetter: return String(localized: "整理失败")
        case .pending: return String(localized: "等待整理")
        case .processing: return String(localized: "正在整理")
        }
    }

    private var stateSymbol: String {
        switch record.processingState {
        case .completed: return sourceSymbol
        case .failed, .deadLetter: return "exclamationmark.circle.fill"
        case .pending: return "clock"
        case .processing: return "wand.and.stars"
        }
    }

    private var stateColor: Color {
        switch record.processingState {
        case .failed, .deadLetter: return .red
        case .pending, .processing: return .newUIPreviewAccent
        case .completed: return .newUIPreviewSecondary
        }
    }

    private var sourceLabel: String {
        switch record.source {
        case .photo: return String(localized: "照片")
        case .spark: return "Spark"
        case .text: return String(localized: "文字")
        }
    }

    private var sourceSymbol: String {
        switch record.source {
        case .photo: return "photo"
        case .spark: return "sparkles"
        case .text: return "doc.text"
        }
    }
}

private struct NewUIPreviewRecordCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
