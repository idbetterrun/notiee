import SwiftUI

struct NewUIPreviewRecordMediaView: View {
    let media: [NewUIPreviewMedia]

    private let spacing: CGFloat = 3
    private let cornerRadius: CGFloat = 6

    @ViewBuilder
    var body: some View {
        switch media.count {
        case 0:
            EmptyView()
        case 1:
            singleImage(media[0])
        case 2:
            HStack(spacing: spacing) {
                tile(media[0], index: 0)
                tile(media[1], index: 1)
            }
            .frame(height: 132)
        case 3:
            HStack(spacing: spacing) {
                tile(media[0], index: 0)
                VStack(spacing: spacing) {
                    tile(media[1], index: 1)
                    tile(media[2], index: 2)
                }
            }
            .frame(height: 176)
        default:
            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    tile(media[0], index: 0)
                    tile(media[1], index: 1)
                }
                HStack(spacing: spacing) {
                    tile(media[2], index: 2)
                    tile(
                        media[3],
                        index: 3,
                        overflowCount: media.count > 4 ? media.count - 4 : nil
                    )
                }
            }
            .frame(height: 178)
        }
    }

    private func singleImage(_ item: NewUIPreviewMedia) -> some View {
        let clampedAspectRatio = min(max(item.aspectRatio, 0.72), 1.8)

        return tile(item, index: 0)
            .aspectRatio(clampedAspectRatio, contentMode: .fill)
            .frame(maxHeight: 280)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
