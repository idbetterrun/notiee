import SwiftUI

#if canImport(Lottie)
import Lottie

struct LottieView: View {
    let name: String
    var loopMode: LottieLoopMode = .loop
    var speed: CGFloat = 1.0
    var contentMode: UIView.ContentMode = .scaleAspectFit

    var body: some View {
        LottieAnimationViewRepresentable(
            name: name,
            loopMode: loopMode,
            speed: speed,
            contentMode: contentMode
        )
        .allowsHitTesting(false)
    }
}

private struct LottieAnimationViewRepresentable: UIViewRepresentable {
    let name: String
    let loopMode: LottieLoopMode
    let speed: CGFloat
    let contentMode: UIView.ContentMode

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: name)
        view.loopMode = loopMode
        view.animationSpeed = speed
        view.contentMode = contentMode
        view.play()
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {}
}

#else

struct LottieView: View {
    let name: String
    var loopMode: Any? = nil
    var speed: CGFloat = 1.0
    var contentMode: Any? = nil

    var body: some View {
        EmptyView()
    }
}

#endif
