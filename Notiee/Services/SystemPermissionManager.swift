import Foundation
import AVFoundation
import Photos
import Speech

@MainActor
final class SystemPermissionManager: ObservableObject {
    static let shared = SystemPermissionManager()
    
    @Published var isRequesting = false
    
    func requestAllPermissions(completion: @escaping () -> Void) {
        isRequesting = true
        
        Task {
            await requestCamera()
            await requestMicrophone()
            await requestPhotoLibrary()
            await requestSpeech()
            
            isRequesting = false
            completion()
        }
    }
    
    private func requestCamera() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
    }
    
    private func requestMicrophone() async {
        if AVAudioSession.sharedInstance().recordPermission == .undetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { _ in
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    private func requestPhotoLibrary() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
    }
    
    private func requestSpeech() async {
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
