import Foundation
import UIKit

/// Note-processing for the Notiee (free) version: the model API keys live on the
/// backend, so the client only ships compressed images + the assembled prompts to
/// `POST /ai/process` and lets the backend run vision → text.
///
/// Reuses `RealAIProcessingService`'s image encoding and JSON parsing so the two
/// paths stay byte-identical where it matters. Notiee-target only.
struct BackendAIProcessingService: AIProcessingService {
    let settingsStore: AppSettingsPersisting
    private let api: BackendAPIClient

    /// 用户选中的模型（`CuratedModelSelection`，按当前档位夹取）。免费档实际仍
    /// 只会拿到免费模型；Phase 4 接真档位后 Pro 用户即可用到所选高级模型。
    private let selection = CuratedModelSelection.live

    /// API-gateway body budget is ~10MB; base64 inflates ~33%, so cap raw bytes.
    private static let maxBodyBytes = 8 * 1024 * 1024
    private static let maxImages = 6

    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live,
         api: BackendAPIClient = .shared) {
        self.settingsStore = settingsStore
        self.api = api
    }

    func process(imagePaths: [String], eventTitle: String?) async throws -> AIProcessingResult {
        let preset = ScenePreset.load()
        let visionModel = selection.visionModelID(for: CurrentEntitlement.tier)
        let textModel = selection.textModelID(for: CurrentEntitlement.tier)

        // 文本提示两条路径都要（后端把它与 OCR 结果拼接；这里传空占位）。
        let enableSummary = settingsStore.loadBool(forKey: UDK.aiEnableSummary, defaultValue: true)
        let enableDetailedContent = settingsStore.loadBool(forKey: UDK.aiEnableDetailedContent, defaultValue: true)
        let textPrompt = AIPromptProvider.textPrompt(
            ocrText: "", enableSummary: enableSummary,
            enableDetailedContent: enableDetailedContent, preset: preset)

        // 低消耗模式：本地 OCR 替代云端视觉，只把文本发后端整理（省视觉成本、更快）。
        let isLowConsumption = UserDefaults.standard.bool(forKey: UDK.labLowConsumptionModeEnabled)

        let body: [String: Any]
        if isLowConsumption {
            let localOCR = try await LocalOCRService.batchRecognize(imagePaths: imagePaths)
            body = [
                "ocrText": localOCR,
                "textModel": textModel,
                "textPrompt": textPrompt,
            ]
        } else {
            // 云端视觉：编码图片（复用 RealAIProcessingService 的 resize/compress）。
            let base64Images = encodeImages(imagePaths: imagePaths)
            guard !base64Images.isEmpty else { throw AIError.imageProcessingFailed }

            let isFullVisionManual = UserDefaults.standard.bool(forKey: UDK.labFullVisionModeEnabled)
            let useFullVision = preset.visionStrategy == .fullVision || isFullVisionManual
            let (visionUserPrompt, visionSystemPrompt) = AIPromptProvider.visionPrompt(
                fullVision: useFullVision, latex: preset.enableLaTeX)

            body = [
                "images": base64Images,
                "visionModel": visionModel,
                "textModel": textModel,
                "visionPrompt": visionUserPrompt,
                "textPrompt": textPrompt,
                "systemVision": visionSystemPrompt,
            ]
        }

        // 3) Call the backend. Long timeout: two upstream calls run serially.
        let json: [String: Any]
        do {
            json = try await api.postJSON(
                path: "ai/process", body: body,
                authorized: true, timeout: BackendAPIClient.Timeout.aiProcess)
        } catch let error as BackendError where error.code == .quotaExceeded {
            // Quota exhausted → graceful local-OCR downgrade (rather than a hard
            // block). Phase 3 wires the "本月 X/N 篇用尽" UI onto this path.
            error.quota?.broadcast()
            return try await localOCRFallback(imagePaths: imagePaths, eventTitle: eventTitle)
        }

        // 4) Piggy-backed quota → feed display state (saves a /me/quota round-trip).
        if let quotaDict = json["quota"] as? [String: Any],
           let quota = BackendQuota(dictionary: quotaDict) {
            quota.broadcast()
        }

        // 5) Parse the structured note (reuse RealAIProcessingService's decoder).
        let ocrText = json["ocrText"] as? String ?? ""
        let content = json["content"] as? String ?? ""
        let tokensUsed = json["tokensUsed"] as? Int ?? 0

        let result = try RealAIProcessingService.parseStructuredNote(
            responseJSON: content, ocrText: ocrText,
            modelsUsed: isLowConsumption ? ["local-ocr", textModel] : [visionModel, textModel])

        return AIProcessingResult(
            title: result.title,
            ocrText: result.ocrText,
            summary: result.summary,
            detailedContent: result.detailedContent,
            todos: result.todos,
            keyPoints: result.keyPoints,
            definitions: result.definitions,
            modelsUsed: result.modelsUsed,
            tokenUsage: tokensUsed
        )
    }

    // MARK: - Helpers

    private func encodeImages(imagePaths: [String]) -> [String] {
        var base64Images: [String] = []
        var byteBudget = Self.maxBodyBytes
        for path in imagePaths.prefix(Self.maxImages) {
            guard let data = LocalImageStore.readImageData(path: path),
                  let image = UIImage(data: data),
                  let jpeg = RealAIProcessingService.resizeAndCompress(image: image) else { continue }
            if jpeg.count > byteBudget { break }
            byteBudget -= jpeg.count
            base64Images.append(jpeg.base64EncodedString())
        }
        return base64Images
    }

    /// Local, on-device OCR fallback used when the monthly quota is spent. Produces
    /// a minimal note (OCR text as detailed content, first line as title) so the
    /// capture still results in a usable record.
    private func localOCRFallback(imagePaths: [String], eventTitle: String?) async throws -> AIProcessingResult {
        let ocrText = try await LocalOCRService.batchRecognize(imagePaths: imagePaths)
        let firstLine = ocrText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let title = eventTitle?.isEmpty == false
            ? eventTitle!
            : (firstLine.isEmpty ? String(localized: "本地识别笔记") : String(firstLine.prefix(15)))
        return AIProcessingResult(
            title: title,
            ocrText: ocrText,
            summary: "",
            detailedContent: ocrText,
            todos: [],
            keyPoints: [],
            definitions: [],
            modelsUsed: ["local-ocr"],
            tokenUsage: 0
        )
    }
}
