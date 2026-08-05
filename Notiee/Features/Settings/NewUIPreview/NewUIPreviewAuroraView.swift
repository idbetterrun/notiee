import Foundation
import MetalKit
import QuartzCore
import SwiftUI

/// A transparent, top-of-page Metal surface for the active-event Hero. The
/// renderer owns GPU lifecycle and motion; SwiftUI supplies only semantic state.
struct NewUIPreviewAuroraBackdrop: UIViewRepresentable {
    let colorHex: String?
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeCoordinator() -> NewUIPreviewAuroraRenderer {
        NewUIPreviewAuroraRenderer()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = true
        view.preferredFramesPerSecond = 30
        view.delegate = context.coordinator

        context.coordinator.attach(to: view)
        context.coordinator.update(
            colorHex: colorHex,
            shouldAnimate: isActive && !reduceMotion && scenePhase == .active
        )
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.update(
            colorHex: colorHex,
            shouldAnimate: isActive && !reduceMotion && scenePhase == .active
        )
    }
}

final class NewUIPreviewAuroraRenderer: NSObject, MTKViewDelegate {
    private weak var view: MTKView?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var isRenderingAvailable = false
    private var isAnimating = false
    private var elapsedTime: Float = 0
    private var lastFrameTimestamp: CFTimeInterval?
    private var colors = NewUIPreviewAuroraColors(hex: nil)

    func attach(to view: MTKView) {
        self.view = view

        guard
            let device = view.device,
            let commandQueue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary(),
            let vertex = library.makeFunction(name: "newUIPreviewAuroraVertex"),
            let fragment = library.makeFunction(name: "newUIPreviewAuroraFragment")
        else {
            view.isHidden = true
            return
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            self.commandQueue = commandQueue
            isRenderingAvailable = true
        } catch {
            view.isHidden = true
        }
    }

    func update(colorHex: String?, shouldAnimate: Bool) {
        colors = NewUIPreviewAuroraColors(hex: colorHex)

        guard isRenderingAvailable, let view else { return }
        guard isAnimating != shouldAnimate else {
            if !shouldAnimate {
                view.setNeedsDisplay()
            }
            return
        }

        isAnimating = shouldAnimate
        if shouldAnimate {
            lastFrameTimestamp = CACurrentMediaTime()
            view.isPaused = false
        } else {
            lastFrameTimestamp = nil
            view.isPaused = true
            view.setNeedsDisplay()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard
            isRenderingAvailable,
            let commandQueue,
            let pipelineState,
            let passDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable
        else {
            return
        }

        updateElapsedTime()

        var uniforms = NewUIPreviewAuroraUniforms(
            time: elapsedTime,
            amplitude: 0.82,
            blend: 0.42,
            resolution: SIMD2(
                max(Float(view.drawableSize.width), 1),
                max(Float(view.drawableSize.height), 1)
            ),
            colors: colors
        )

        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<NewUIPreviewAuroraUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func updateElapsedTime() {
        guard isAnimating else { return }

        let now = CACurrentMediaTime()
        defer { lastFrameTimestamp = now }
        guard let lastFrameTimestamp else { return }

        // Cap the delta after app interruptions so resuming remains gentle.
        elapsedTime += Float(min(now - lastFrameTimestamp, 1.0 / 15.0)) * 0.18
    }
}

private struct NewUIPreviewAuroraUniforms {
    var time: Float
    var amplitude: Float
    var blend: Float
    var padding: Float = 0
    var resolution: SIMD2<Float>
    var resolutionPadding = SIMD2<Float>(repeating: 0)
    var color0: SIMD4<Float>
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>

    init(
        time: Float,
        amplitude: Float,
        blend: Float,
        resolution: SIMD2<Float>,
        colors: NewUIPreviewAuroraColors
    ) {
        self.time = time
        self.amplitude = amplitude
        self.blend = blend
        self.resolution = resolution
        color0 = SIMD4(colors.light, 1)
        color1 = SIMD4(colors.base, 1)
        color2 = SIMD4(colors.deep, 1)
    }
}

private struct NewUIPreviewAuroraColors {
    let light: SIMD3<Float>
    let base: SIMD3<Float>
    let deep: SIMD3<Float>

    init(hex: String?) {
        let base = Self.parse(hex) ?? SIMD3(9.0 / 255.0, 197.0 / 255.0, 118.0 / 255.0)
        self.base = base
        light = Self.mix(base, SIMD3(repeating: 1), amount: 0.38)
        deep = Self.mix(base, SIMD3(repeating: 0), amount: 0.28)
    }

    private static func parse(_ hex: String?) -> SIMD3<Float>? {
        guard let hex else { return nil }

        let value = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }

        return SIMD3(
            Float((rgb >> 16) & 0xFF) / 255,
            Float((rgb >> 8) & 0xFF) / 255,
            Float(rgb & 0xFF) / 255
        )
    }

    private static func mix(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>, amount: Float) -> SIMD3<Float> {
        lhs + (rhs - lhs) * amount
    }
}
