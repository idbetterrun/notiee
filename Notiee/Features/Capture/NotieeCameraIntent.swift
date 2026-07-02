import Foundation
import AppIntents

@available(iOS 18.0, *)
struct NotieeCameraIntent: CameraCaptureIntent {
    #if NOTIEE_PLUS
    static var title: LocalizedStringResource = "Notiee+ 拍记"
    static var description: IntentDescription = "快速启动 Notiee+ 并进入拍记页"
    #else
    static var title: LocalizedStringResource = "Notiee 拍记"
    static var description: IntentDescription = "快速启动 Notiee 并进入拍记页"
    #endif
    
    @MainActor
    func perform() async throws -> some IntentResult {
        // AppIntents 会自动拉起应用，并可以带上特定的上下文
        return .result()
    }
}
