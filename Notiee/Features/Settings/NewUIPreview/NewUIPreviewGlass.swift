import SwiftUI

extension Color {
    static let newUIPreviewAccent = Color(red: 9.0 / 255.0, green: 197.0 / 255.0, blue: 118.0 / 255.0)
}

extension View {
    /// 把材质直接加在控件本身上。加在独立的背景层上会把前面的文字也一起模糊掉。
    /// iOS 26 以下没有 Liquid Glass，直接降级为无材质。
    @ViewBuilder
    func newUIPreviewGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                self.glassEffect(.clear.interactive(), in: shape)
            } else {
                self.glassEffect(.clear, in: shape)
            }
        } else {
            self.background(.ultraThinMaterial.opacity(0.9), in: shape)
        }
    }
}

struct NewUIPreviewCircleButton: View {
    let symbol: String
    let label: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? Color.newUIPreviewAccent : .white.opacity(0.9))
                .frame(width: 58, height: 58)
                .newUIPreviewGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(NewUIPreviewPressStyle())
        .accessibilityLabel(label)
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
