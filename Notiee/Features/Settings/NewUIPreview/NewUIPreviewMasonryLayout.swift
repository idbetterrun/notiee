import SwiftUI

struct NewUIPreviewMasonryGeometry {
    static func columnWidth(
        containerWidth: CGFloat,
        columns: Int,
        spacing: CGFloat
    ) -> CGFloat {
        let columnCount = max(columns, 1)
        let safeSpacing = max(spacing, 0)
        let availableWidth = max(containerWidth - safeSpacing * CGFloat(columnCount - 1), 0)
        return availableWidth / CGFloat(columnCount)
    }

    static func frames(
        itemSizes: [CGSize],
        containerWidth: CGFloat,
        columns: Int,
        spacing: CGFloat
    ) -> [CGRect] {
        guard !itemSizes.isEmpty else { return [] }

        let columnCount = max(columns, 1)
        let safeSpacing = max(spacing, 0)
        let columnWidth = columnWidth(
            containerWidth: containerWidth,
            columns: columnCount,
            spacing: safeSpacing
        )
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        return itemSizes.map { itemSize in
            let column = columnHeights.indices.min { lhs, rhs in
                if columnHeights[lhs] == columnHeights[rhs] {
                    return lhs < rhs
                }
                return columnHeights[lhs] < columnHeights[rhs]
            } ?? 0
            let itemHeight = max(itemSize.height, 0)
            let y = columnHeights[column] == 0 ? 0 : columnHeights[column] + safeSpacing
            let frame = CGRect(
                x: CGFloat(column) * (columnWidth + safeSpacing),
                y: y,
                width: columnWidth,
                height: itemHeight
            )
            columnHeights[column] = frame.maxY
            return frame
        }
    }

    static func contentHeight(for frames: [CGRect]) -> CGFloat {
        frames.map(\.maxY).max() ?? 0
    }
}

struct NewUIPreviewMasonryLayout: Layout {
    let columns: Int
    let spacing: CGFloat

    struct Cache {}

    init(columns: Int = 2, spacing: CGFloat = 12) {
        self.columns = max(columns, 1)
        self.spacing = max(spacing, 0)
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let width = resolvedWidth(for: proposal)
        let frames = measuredFrames(width: width, subviews: subviews)
        return CGSize(
            width: width,
            height: NewUIPreviewMasonryGeometry.contentHeight(for: frames)
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let frames = measuredFrames(width: bounds.width, subviews: subviews)

        for (index, subview) in subviews.enumerated() where index < frames.count {
            let frame = frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func resolvedWidth(for proposal: ProposedViewSize) -> CGFloat {
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            return max(proposedWidth, 0)
        }
        return 0
    }

    private func measuredFrames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let safeWidth = max(width, 0)
        let columnWidth = NewUIPreviewMasonryGeometry.columnWidth(
            containerWidth: safeWidth,
            columns: columns,
            spacing: spacing
        )
        let itemSizes = subviews.map { subview in
            let measured = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            return CGSize(
                width: columnWidth,
                height: measured.height.isFinite ? max(measured.height, 0) : 0
            )
        }

        return NewUIPreviewMasonryGeometry.frames(
            itemSizes: itemSizes,
            containerWidth: safeWidth,
            columns: columns,
            spacing: spacing
        )
    }
}
