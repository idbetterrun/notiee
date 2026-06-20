import SwiftUI

extension View {
    /// 图标按钮：iOS 26 用玻璃按钮样式，低版本保持原样（裸图标 + tint）。
    /// 应用在 `Button { } label: { ... }` 上。
    @ViewBuilder
    func glassIconButton(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self
        }
    }

    /// 浮层表面（输入栏 / chip / 胶囊）：iOS 26 用 glassEffect，低版本用 ultraThinMaterial。
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                self.glassEffect(.regular.tint(.accentColor), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// 相邻玻璃元素的融合容器：iOS 26 用 GlassEffectContainer，低版本透传。
struct AdaptiveGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 16) {
        AdaptiveGlassContainer {
            HStack(spacing: 12) {
                Button { } label: { Image(systemName: "square.and.pencil") }.glassIconButton()
                Button { } label: { Image(systemName: "plus") }.glassIconButton(prominent: true)
            }
        }
        Text("surface").padding().glassSurface(in: RoundedRectangle(cornerRadius: 16))
        Text("capsule").padding().glassSurface(in: Capsule(), prominent: true)
    }
    .padding()
}
#endif
