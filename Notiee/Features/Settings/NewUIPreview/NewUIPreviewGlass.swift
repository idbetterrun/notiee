import SwiftUI

enum NewUIPreviewBrand {
    static let accentHex = "#09C576"
    static let accent = Color(
        red: 9.0 / 255.0,
        green: 197.0 / 255.0,
        blue: 118.0 / 255.0
    )
}

enum NewUIPreviewEdgeFadeEdge {
    case top
    case bottom
}

struct NewUIPreviewDetailChromeMetrics {
    static let topControlInset: CGFloat = 8
    static let topControlHeight: CGFloat = 50
    static let topFadeRunway: CGFloat = 46
    static let bottomControlInset: CGFloat = 8
    static let bottomControlHeight: CGFloat = 56
    static let bottomFadeRunway: CGFloat = 62
    static let documentClearance: CGFloat = 16

    static func topFadeHeight(safeAreaTop: CGFloat) -> CGFloat {
        max(0, safeAreaTop) + topControlInset + topControlHeight + topFadeRunway
    }

    static func bottomFadeHeight(safeAreaBottom: CGFloat) -> CGFloat {
        max(0, safeAreaBottom) + bottomControlInset + bottomControlHeight + bottomFadeRunway
    }

    static func documentBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        bottomFadeHeight(safeAreaBottom: safeAreaBottom) + documentClearance
    }
}

struct NewUIPreviewRecordTransitionKey: Hashable {
    let recordID: UUID
    let origin: NewUIPreviewRecordOrigin
}

extension Color {
    static let newUIPreviewAccent = NewUIPreviewBrand.accent
    static let newUIPreviewBackground = Color(uiColor: .systemBackground)
    static let newUIPreviewPrimary = Color.primary
    static let newUIPreviewSecondary = Color.secondary
}

extension View {
    func newUIPreviewGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(NewUIPreviewGlassModifier(shape: shape, interactive: interactive))
    }

    @ViewBuilder
    func newUIPreviewRecordTransitionSurface(
        recordID: UUID?,
        origin: NewUIPreviewRecordOrigin?,
        namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        if let recordID, let origin, let namespace {
            matchedGeometryEffect(
                id: NewUIPreviewRecordTransitionKey(recordID: recordID, origin: origin),
                in: namespace,
                properties: .frame,
                anchor: .center,
                isSource: isSource
            )
        } else {
            self
        }
    }
}

private struct NewUIPreviewGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(uiColor: .secondarySystemBackground), in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.14), lineWidth: 0.75))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                content.glassEffect(.clear.interactive(), in: shape)
            } else {
                content.glassEffect(.clear, in: shape)
            }
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

struct NewUIPreviewGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}

struct NewUIPreviewEdgeFade: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let edge: NewUIPreviewEdgeFadeEdge
    let height: CGFloat

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(uiColor: .systemBackground).opacity(0.96)
            } else {
                Rectangle().fill(.regularMaterial)
                Color(uiColor: .systemBackground).opacity(0.18)
            }
        }
        .mask(maskGradient)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var maskGradient: LinearGradient {
        let stops: [Gradient.Stop]
        switch edge {
        case .top:
            stops = [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.92), location: 0.46),
                .init(color: .clear, location: 1)
            ]
        case .bottom:
            stops = [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.92), location: 0.54),
                .init(color: .black, location: 1)
            ]
        }
        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct NewUIPreviewCircleButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Color.newUIPreviewAccent : Color.newUIPreviewPrimary.opacity(0.9))
                .frame(width: 50, height: 50)
                .contentShape(Circle())
                .newUIPreviewGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(NewUIPreviewPressStyle())
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct NewUIPreviewPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}
