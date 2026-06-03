import SwiftUI

// MARK: - Spark Background View (V3: fixed animation math, slower, proper keyboard positioning)

struct SparkBackgroundView: View {
    let state: SparkState
    let isInputFocused: Bool
    let keyboardHeight: CGFloat

    @State private var focusedBlend: Double = 0
    @State private var sendProgress: Double = 0
    @State private var sendAnimating: Bool = false

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let effectiveFocused = isInputFocused || state == .loading
                let effectiveSending = sendAnimating

                let blobs: [(color: Color, phaseOff: Double, scale: Double)] = [
                    (Color(red: 0.361, green: 0.682, blue: 0.980), 0.0, 1.0),
                    (Color(red: 0.325, green: 0.980, blue: 0.671), 1.8, 0.85),
                    (Color(red: 0.361, green: 0.682, blue: 0.980), 3.2, 0.65),
                    (Color(red: 0.325, green: 0.980, blue: 0.671), 5.1, 0.75),
                    (Color(red: 0.40, green: 0.80, blue: 0.92), 7.4, 0.55),
                ]

                for blob in blobs {
                    let (px, py) = blobPosition(
                        t: t, phase: blob.phaseOff, size: size,
                        keyboardHeight: keyboardHeight, focused: effectiveFocused,
                        sending: effectiveSending, sendProgress: sendProgress
                    )
                    let r = blobRadius(size: size, scale: blob.scale, t: t,
                                       phase: blob.phaseOff,
                                       focused: effectiveFocused,
                                       sending: effectiveSending, sendProgress: sendProgress)
                    let op = blobOpacity(t: t, phase: blob.phaseOff,
                                         focused: effectiveFocused,
                                         sending: effectiveSending, sendProgress: sendProgress)

                    let gradient = Gradient(colors: [
                        blob.color.opacity(op),
                        blob.color.opacity(op * 0.45),
                        blob.color.opacity(0)
                    ])
                    let radial = GraphicsContext.Shading.radialGradient(
                        gradient,
                        center: CGPoint(x: px, y: py),
                        startRadius: 0,
                        endRadius: r
                    )
                    let rect = CGRect(
                        x: px - r * 1.15,
                        y: py - r * 0.85,
                        width: r * 2.3,
                        height: r * 1.7
                    )
                    context.fill(Path(ellipseIn: rect), with: radial)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: focusedBlend)
        .onChange(of: isInputFocused) { _, newVal in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                focusedBlend = newVal ? 1.0 : 0.0
            }
        }
        .onChange(of: state) { _, newState in
            if newState == .loading {
                sendAnimating = true
                sendProgress = 0
                withAnimation(.easeOut(duration: 2.5)) {
                    sendProgress = 1.0
                }
            }
            if newState == .loaded || newState == .idle {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    sendAnimating = false
                    sendProgress = 0
                }
            }
        }
    }
}

// MARK: - Multi-octave organic noise (8 octaves, prime frequencies, slowed down)

private func organicNoise(t: Double, phase: Double) -> (x: Double, y: Double) {
    // Slow down by factor 0.7 compared to V2
    let slowedT = t * 0.7
    let freqs: [Double] = [0.31, 0.47, 0.73, 1.07, 1.37, 1.79, 2.23, 2.83]
    let amps: [Double] = [0.55, 0.28, 0.18, 0.10, 0.06, 0.04, 0.025, 0.015]
    var x: Double = 0
    var y: Double = 0
    for i in 0..<freqs.count {
        let fi = freqs[i]
        let ai = amps[i]
        x += sin(slowedT * fi + phase * 1.3) * ai + sin(slowedT * fi * 0.61 + phase * 2.7) * ai * 0.5
        y += cos(slowedT * fi * 0.89 + phase * 1.1 + 1.4) * ai + cos(slowedT * fi * 0.43 + phase * 3.1) * ai * 0.5
    }
    return (x, y)
}

private func blobPosition(
    t: TimeInterval, phase: Double, size: CGSize,
    keyboardHeight: CGFloat, focused: Bool, sending: Bool, sendProgress: Double
) -> (CGFloat, CGFloat) {
    let cx = size.width / 2
    let cy = size.height / 2
    let noise = organicNoise(t: t, phase: phase)

    if sending {
        // Slow upward surge driven by sendProgress (0 -> 1 over 2.5s)
        let cycle = sendProgress
        let surgeY = cy * 0.8 - CGFloat(cycle) * size.height * 0.65
        let spreadX = CGFloat(cycle) * size.width * 0.4
        return (
            cx + noise.x * spreadX * 0.5,
            max(surgeY + noise.y * 20, size.height * 0.04)
        )
    }

    if focused {
        // Blobs stay right above the input bar, not under keyboard
        let tx = cx
        let ty = max(size.height - keyboardHeight - 100, size.height * 0.45)
        return (
            tx + noise.x * size.width * 0.05,
            ty + noise.y * size.height * 0.03
        )
    }

    // Idle: wide organic drift (amplitude reduced by 30%)
    let rx = size.width * 0.22
    let ry = size.height * 0.20
    return (
        cx + noise.x * rx,
        cy * 0.9 + noise.y * ry
    )
}

private func blobRadius(
    size: CGSize, scale: Double,
    t: TimeInterval, phase: Double,
    focused: Bool, sending: Bool, sendProgress: Double
) -> CGFloat {
    let base = max(size.width, size.height) * 0.42 * scale

    if sending {
        return base * (0.55 + CGFloat(sendProgress) * 1.0)
    }
    if focused {
        return base * 0.52
    }
    // Idle: subtle breathing, slower by factor 0.7
    return base * (1.0 + sin(t * 0.30 + phase) * 0.025)
}

private func blobOpacity(
    t: TimeInterval, phase: Double,
    focused: Bool, sending: Bool, sendProgress: Double
) -> Double {
    if sending {
        if sendProgress < 0.55 {
            return 0.16 + sendProgress / 0.55 * 0.14
        } else {
            return 0.30 - (sendProgress - 0.55) / 0.45 * 0.18
        }
    }
    if focused {
        return 0.17 + sin(t * 0.55 + phase) * 0.03
    }
    return 0.10 + sin(t * 0.20 + phase) * 0.02
}

#Preview {
    SparkBackgroundView(state: .idle, isInputFocused: false, keyboardHeight: 0)
        .preferredColorScheme(.dark)
}
