import AVFoundation
import UIKit

@MainActor
final class CameraManager: NSObject, ObservableObject {
    enum Status {
        case unconfigured
        case unauthorized
        case ready
        case failed
    }

    @Published private(set) var status: Status = .unconfigured
    @Published private(set) var capturedImage: UIImage?
    @Published private(set) var currentZoomFactor: CGFloat = 1.0
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    private var lensZoomRange: ClosedRange<CGFloat> = 1.0...1.0

    /// AVFoundation session objects are confined to `sessionQueue`. The wrapper is
    /// sendable because its mutable members are accessed only on that serial queue.
    private final class SessionState: @unchecked Sendable {
        let session = AVCaptureSession()
        let photoOutput = AVCapturePhotoOutput()
        var videoDevice: AVCaptureDevice?
        var isConfigured = false
    }

    private let sessionState = SessionState()
    private let sessionQueue = DispatchQueue(label: "com.notiee.camera.session")

    var session: AVCaptureSession { sessionState.session }

    struct LensPreset {
        let factor: CGFloat
        let label: String
    }

    var availableLensPresets: [LensPreset] {
        var presets: [LensPreset] = []
        let minZoom = lensZoomRange.lowerBound
        let maxZoom = lensZoomRange.upperBound

        if minZoom < 0.9 {
            presets.append(LensPreset(factor: minZoom * 2, label: "超广角 0.5x"))
        }
        presets.append(LensPreset(factor: 1.0, label: "广角 1x"))
        if maxZoom >= 2.0 {
            presets.append(LensPreset(factor: 2.0, label: "2x"))
        }
        if maxZoom >= 5.0 {
            presets.append(LensPreset(factor: 5.0, label: "长焦 5x"))
        } else if maxZoom >= 3.0 {
            presets.append(LensPreset(factor: 3.0, label: "长焦 3x"))
        }
        if maxZoom > (presets.last?.factor ?? 2.0) {
            let highZoom = min(maxZoom, 10.0)
            presets.append(LensPreset(factor: highZoom, label: String(format: "%.0fx", highZoom)))
        }
        return presets
    }

    func lensLabel(for factor: CGFloat) -> String {
        for preset in availableLensPresets {
            if abs(preset.factor - factor) < 0.1 {
                return preset.label
            }
        }
        if factor <= 1.05 { return "1x" }
        return String(format: "%.1fx", factor)
    }

    func checkPermissionsAndConfigure() {
        #if targetEnvironment(simulator)
        Task { @MainActor in self.status = .ready }
        return
        #endif

        if status == .ready {
            startSession()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.status = .unauthorized
                    }
                }
            }
        case .denied, .restricted:
            status = .unauthorized
        @unknown default:
            status = .failed
        }
    }

    private func configureSession() {
        let state = sessionState
        sessionQueue.async { [weak self, state] in
            guard let self else { return }

            // Configure exactly once. A second pass would re-add inputs/outputs to
            // an already-wired session and can deadlock it; just (re)start instead.
            guard !state.isConfigured else {
                if !state.session.isRunning { state.session.startRunning() }
                return
            }

            state.session.beginConfiguration()
            state.session.sessionPreset = .photo

            // Add video input
            let deviceTypes: [AVCaptureDevice.DeviceType] = [
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInDualCamera,
                .builtInWideAngleCamera
            ]
            
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .back
            )
            
            if let videoDevice = discoverySession.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                state.videoDevice = videoDevice
                guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                      state.session.canAddInput(videoDeviceInput) else {
                    Task { @MainActor in self.status = .failed }
                    state.session.commitConfiguration()
                    return
                }
                state.session.addInput(videoDeviceInput)
            }

            // Add photo output
            guard state.session.canAddOutput(state.photoOutput) else {
                Task { @MainActor in self.status = .failed }
                state.session.commitConfiguration()
                return
            }
            state.session.addOutput(state.photoOutput)

            state.session.commitConfiguration()
            state.isConfigured = true

            // Start on the session queue right away so the first frame isn't
            // gated behind a hop to the main actor (which made cold start feel
            // slow). Publish `.ready` and sync zoom back on the main actor.
            state.session.startRunning()

            let minZoom = state.videoDevice?.minAvailableVideoZoomFactor ?? 1
            let maxZoom = state.videoDevice?.maxAvailableVideoZoomFactor ?? 1
            let currentZoom = state.videoDevice?.videoZoomFactor ?? 1

            Task { @MainActor in
                self.status = .ready
                self.lensZoomRange = minZoom...maxZoom
                self.currentZoomFactor = currentZoom
            }
        }
    }

    func startSession() {
        let state = sessionState
        sessionQueue.async { [state] in
            guard state.isConfigured, !state.session.isRunning else { return }
            state.session.startRunning()
        }
    }

    func stopSession() {
        let state = sessionState
        sessionQueue.async { [state] in
            guard state.session.isRunning else { return }
            state.session.stopRunning()
        }
    }

    // MARK: - Photo Capture

    func setZoom(factor: CGFloat) {
        let state = sessionState
        sessionQueue.async { [weak self, state] in
            guard let device = state.videoDevice else { return }
            do {
                try device.lockForConfiguration()
                let clamp = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamp
                device.unlockForConfiguration()
                Task { @MainActor in self?.currentZoomFactor = clamp }
            } catch {
                print("Failed to set zoom: \(error)")
            }
        }
    }

    func capturePhoto() {
        guard status == .ready else { return }
        
        #if targetEnvironment(simulator)
        Task { @MainActor in
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1920))
            let fakeImage = renderer.image { ctx in
                UIColor.darkGray.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
                
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 100, weight: .bold),
                    .foregroundColor: UIColor.white
                ]
                let text = "Simulator Photo" as NSString
                text.draw(at: CGPoint(x: 100, y: 900), withAttributes: attrs)
            }
            self.capturedImage = fakeImage
        }
        return
        #endif

        let state = sessionState
        let selectedFlashMode = flashMode
        sessionQueue.async { [weak self, state] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            if state.photoOutput.supportedFlashModes.contains(selectedFlashMode) {
                settings.flashMode = selectedFlashMode
            }
            
            if let videoConnection = state.photoOutput.connection(with: .video) {
                // Ensure orientation is correct for portrait (common on iPhones)
                if videoConnection.isVideoRotationAngleSupported(90) {
                    videoConnection.videoRotationAngle = 90
                }
            }

            state.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error = error {
            print("Error capturing photo: \(error.localizedDescription)")
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            return
        }

        Task { @MainActor in
            self.capturedImage = image
        }
    }
}
