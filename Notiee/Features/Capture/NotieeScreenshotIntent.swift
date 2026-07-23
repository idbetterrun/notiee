import AppIntents
import UniformTypeIdentifiers

@available(iOS 18.0, *)
struct NotieeScreenshotIntent: AppIntent {
    #if NOTIEE_PLUS
    static var title: LocalizedStringResource = "保存截图到 Notiee+"
    #else
    static var title: LocalizedStringResource = "保存截图到 Notiee"
    #endif
    static var description = IntentDescription("将截图保存为拍记并在后台整理")
    static var openAppWhenRun = false

    @Parameter(
        title: "截图",
        supportedContentTypes: [.image],
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let screenshot else { throw ScreenshotImportError.missingImage }
        _ = try ScreenshotImportService(
            store: NotieeProcessingRuntime.shared.store,
            imageSaver: LocalImageStore.shared,
            scheduler: AIBackgroundTaskScheduler.shared
        ).importScreenshotData(screenshot.data)
        return .result(dialog: "截图已保存，正在后台整理")
    }
}

@available(iOS 18.0, *)
struct NotieeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NotieeScreenshotIntent(),
            phrases: ["保存截图到 \(.applicationName)"],
            shortTitle: "保存截图",
            systemImageName: "camera.viewfinder"
        )
    }
}
