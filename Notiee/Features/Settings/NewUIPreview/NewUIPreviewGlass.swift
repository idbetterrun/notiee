import SwiftUI

extension Color {
    static let newUIPreviewAccent = Color(red: 9.0 / 255.0, green: 197.0 / 255.0, blue: 118.0 / 255.0)
    static let newUIPreviewBackground = Color(uiColor: .systemBackground)
    static let newUIPreviewPrimary = Color.primary
    static let newUIPreviewSecondary = Color.secondary
}

extension View {
    func newUIPreviewGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(NewUIPreviewGlassModifier(shape: shape, interactive: interactive))
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
