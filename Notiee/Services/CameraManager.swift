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
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.notiee.camera.session")
    private var videoDevice: AVCaptureDevice?

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
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

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
                self.videoDevice = videoDevice
                guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
                      self.session.canAddInput(videoDeviceInput) else {
                    Task { @MainActor in self.status = .failed }
                    self.session.commitConfiguration()
                    return
                }
                self.session.addInput(videoDeviceInput)
            }

            // Add photo output
            guard self.session.canAddOutput(self.photoOutput) else {
                Task { @MainActor in self.status = .failed }
                self.session.commitConfiguration()
                return
            }
            self.session.addOutput(self.photoOutput)

            self.session.commitConfiguration()

            Task { @MainActor in
                self.status = .ready
                self.startSession()
            }
        }
    }

    func startSession() {
        guard status == .ready else { return }
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: - Photo Capture

    func setZoom(factor: CGFloat) {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
            device.unlockForConfiguration()
        } catch {
            print("Failed to set zoom: \(error)")
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

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()
            if self.photoOutput.supportedFlashModes.contains(self.flashMode) {
                settings.flashMode = self.flashMode
            }
            
            if let videoConnection = self.photoOutput.connection(with: .video) {
                // Ensure orientation is correct for portrait (common on iPhones)
                if videoConnection.isVideoRotationAngleSupported(90) {
                    videoConnection.videoRotationAngle = 90
                }
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
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
