import SwiftUI

struct NewUIPreviewRecordMediaLayout: Equatable {
    let frames: [CGRect]
    let height: CGFloat
}

struct NewUIPreviewRecordMediaGeometry {
    static func layout(
        media: [NewUIPreviewMedia],
        width: CGFloat,
        spacing: CGFloat
    ) -> NewUIPreviewRecordMediaLayout {
        let safeWidth = max(width, 0)
        let safeSpacing = max(spacing, 0)

        switch media.count {
        case 0:
            return NewUIPreviewRecordMediaLayout(frames: [], height: 0)
        case 1:
            let ratio = min(max(media[0].aspectRatio, 0.72), 1.8)
            let height = min(safeWidth / ratio, 280)
            return NewUIPreviewRecordMediaLayout(
                frames: [CGRect(x: 0, y: 0, width: safeWidth, height: height)],
                height: height
            )
        case 2:
            let height = safeWidth / 1.5
            let tileWidth = max((safeWidth - safeSpacing) / 2, 0)
            return NewUIPreviewRecordMediaLayout(
                frames: [
                    CGRect(x: 0, y: 0, width: tileWidth, height: height),
                    CGRect(x: tileWidth + safeSpacing, y: 0, width: tileWidth, height: height)
                ],
                height: height
            )
        case 3:
            let height = min(safeWidth, 320)
            let usableWidth = max(safeWidth - safeSpacing, 0)
            let leadingWidth = usableWidth * 0.6
            let trailingWidth = usableWidth - leadingWidth
            let trailingHeight = max((height - safeSpacing) / 2, 0)
            return NewUIPreviewRecordMediaLayout(
                frames: [
                    CGRect(x: 0, y: 0, width: leadingWidth, height: height),
                    CGRect(x: leadingWidth + safeSpacing, y: 0, width: trailingWidth, height: trailingHeight),
                    CGRect(
                        x: leadingWidth + safeSpacing,
                        y: trailingHeight + safeSpacing,
                        width: trailingWidth,
                        height: trailingHeight
                    )
                ],
                height: height
            )
        default:
            let height = min(safeWidth, 320)
            let tileWidth = max((safeWidth - safeSpacing) / 2, 0)
            let tileHeight = max((height - safeSpacing) / 2, 0)
            return NewUIPreviewRecordMediaLayout(
                frames: [
                    CGRect(x: 0, y: 0, width: tileWidth, height: tileHeight),
                    CGRect(x: tileWidth + safeSpacing, y: 0, width: tileWidth, height: tileHeight),
                    CGRect(x: 0, y: tileHeight + safeSpacing, width: tileWidth, height: tileHeight),
                    CGRect(
                        x: tileWidth + safeSpacing,
                        y: tileHeight + safeSpacing,
                        width: tileWidth,
                        height: tileHeight
                    )
                ],
                height: height
            )
        }
    }
}

struct NewUIPreviewRecordMediaView: View {
    let media: [NewUIPreviewMedia]
    let availableWidth: CGFloat

    private let spacing: CGFloat = 3
    private let cornerRadius: CGFloat = 6

    var body: some View {
        let layout = NewUIPreviewRecordMediaGeometry.layout(
            media: media,
            width: availableWidth,
            spacing: spacing
        )

        return ZStack(alignment: .topLeading) {
            ForEach(Array(media.prefix(layout.frames.count).enumerated()), id: \.element.id) { index, item in
                let frame = layout.frames[index]
                tile(
                    item,
                    index: index,
                    overflowCount: index == 3 && media.count > 4 ? media.count - 4 : nil
                )
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
            }
        }
        .frame(width: max(availableWidth, 0), height: layout.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private func tile(
        _ item: NewUIPreviewMedia,
        index: Int,
        overflowCount: Int? = nil
    ) -> some View {
        Image(item.imageName)
            .resizable()
            .scaledToFill()
            .clipped()
            .overlay {
                if let overflowCount {
                    ZStack {
                        Color.black.opacity(0.46)
                        Text("+\(overflowCount)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityLabel("记录图片 \(index + 1)")
    }
}
