import Foundation
import UIKit

struct RealAIProcessingService: AIProcessingService {
    let settingsStore: AppSettingsPersisting

    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        self.settingsStore = settingsStore
    }

    func process(imagePaths: [String], eventTitle: String?) async throws -> AIProcessingResult {
        let textConfig = settingsStore.loadConfiguration(for: .text)
        let visionConfig = settingsStore.loadConfiguration(for: .vision)
        let preset = ScenePreset.load()

        guard textConfig.isComplete, visionConfig.isComplete else {
            throw AIError.missingConfiguration
        }

        var base64Images: [String] = []
        for path in imagePaths {
            guard let data = LocalImageStore.readImageData(path: path),
                  let image = UIImage(data: data) else { continue }
            if let data = resizeAndCompress(image: image) {
                base64Images.append(data.base64EncodedString())
            }
        }

        guard !base64Images.isEmpty else {
            throw AIError.imageProcessingFailed
        }

        let (ocrText, visionTokens) = try await callVisionModel(
            config: visionConfig,
            base64Images: base64Images,
            imagePaths: imagePaths,
            preset: preset
        )

        let (result, textTokens) = try await callTextModel(
            config: textConfig,
            visionConfig: visionConfig,
            ocrText: ocrText,
            eventTitle: eventTitle,
            preset: preset
        )

        return AIProcessingResult(
            title: result.title,
            ocrText: result.ocrText,
            summary: result.summary,
            detailedContent: result.detailedContent,
            todos: result.todos,
            keyPoints: result.keyPoints,
            definitions: result.definitions,
            modelsUsed: result.modelsUsed,
            tokenUsage: visionTokens + textTokens
        )
    }

    private func resizeAndCompress(image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1024
        var size = image.size
        if size.width > maxDimension || size.height > maxDimension {
            let ratio = size.width / size.height
            if size.width > size.height {
                size.width = maxDimension
                size.height = maxDimension / ratio
            } else {
                size.height = maxDimension
                size.width = maxDimension * ratio
            }
        }

        let renderer = UIGraphicsImageRenderer(size: size)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resizedImage.jpegData(compressionQuality: 0.6)
    }

    private func callVisionModel(config: AIModelConfiguration, base64Images: [String], imagePaths: [String], preset: ScenePreset) async throws -> (String, Int) {
        let isLowConsumption = UserDefaults.standard.bool(forKey: UDK.labLowConsumptionModeEnabled)

        if isLowConsumption {
            let localText = try await LocalOCRService.batchRecognize(imagePaths: imagePaths)
            return (localText, 0)
        }

        let endpoint = config.activeEndpoint
        let protocolType = config.activeProtocol

        let isFullVisionManual = UserDefaults.standard.bool(forKey: UDK.labFullVisionModeEnabled)
        let useFullVision = preset.visionStrategy == .fullVision || isFullVisionManual

        let (prompt, systemPrompt) = AIPromptProvider.visionPrompt(fullVision: useFullVision, latex: preset.enableLaTeX)
        // systemPrompt is now returned by AIPromptProvider.visionPrompt()

        // LaTeX suffix is now handled by AIPromptProvider.visionPrompt()

        var contentArray: [[String: Any]] = []
        for base64 in base64Images {
            contentArray.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)"
                ]
            ])
        }
        contentArray.append([
            "type": "text",
            "text": prompt
        ])

        let messages: [[String: Any]] = [
            [
                "role": "system",
                "content": systemPrompt
            ],
            [
                "role": "user",
                "content": contentArray
            ]
        ]

        let payload: [String: Any] = [
            "model": config.modelName,
            "messages": messages,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"

        var apiKeyHeader = "Bearer \(config.apiKey)"
        if protocolType == .anthropic {
            apiKeyHeader = config.apiKey
            request.setValue(apiKeyHeader, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue(apiKeyHeader, forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw AIError.apiError(errString)
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            let tokens = (json["usage"] as? [String: Any])?["total_tokens"] as? Int ?? 0
            return (content, tokens)
        }

        throw AIError.parsingFailed
    }

    private func callTextModel(config: AIModelConfiguration, visionConfig: AIModelConfiguration, ocrText: String, eventTitle: String?, preset: ScenePreset) async throws -> (AIProcessingResult, Int) {
        let endpoint = config.activeEndpoint
        let protocolType = config.activeProtocol

        let enableSummary = settingsStore.loadBool(forKey: UDK.aiEnableSummary, defaultValue: true)
        let enableDetailedContent = settingsStore.loadBool(forKey: UDK.aiEnableDetailedContent, defaultValue: true)

        let prompt = AIPromptProvider.textPrompt(
            ocrText: ocrText,
            enableSummary: enableSummary,
            enableDetailedContent: enableDetailedContent,
            preset: preset
        )

        let responseJSON: String
        let tokens: Int
        if protocolType == .openai {
            let res = try await OpenAICaller.callText(endpoint: endpoint, model: config.modelName, apiKey: config.apiKey, prompt: prompt)
            responseJSON = res.0
            tokens = res.1
        } else {
            let res = try await AnthropicCaller.callText(endpoint: endpoint, model: config.modelName, apiKey: config.apiKey, prompt: prompt)
            responseJSON = res.0
            tokens = res.1
        }

        let cleanedJSON = responseJSON.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleanedJSON.data(using: .utf8) else {
            throw AIError.parsingFailed
        }

        struct ParsedOutput: Decodable {
            let title: String
            let summary: String
            let detailedContent: String?
            let todos: [String]
            let keyPoints: [String]?
            let definitions: [ParsedDefinition]?
        }

        struct ParsedDefinition: Decodable {
            let term: String
            let explanation: String
        }

        do {
            let parsed = try JSONDecoder().decode(ParsedOutput.self, from: data)
            let result = AIProcessingResult(
                title: parsed.title,
                ocrText: ocrText,
                summary: parsed.summary,
                detailedContent: parsed.detailedContent ?? "无详细内容",
                todos: parsed.todos,
                keyPoints: parsed.keyPoints ?? [],
                definitions: (parsed.definitions ?? []).map { KeyDefinition(term: $0.term, explanation: $0.explanation) },
                modelsUsed: [visionConfig.modelName, config.modelName],
                tokenUsage: 0
            )
            return (result, tokens)
        } catch {
            print("Failed to decode JSON: \(error)")
            throw AIError.parsingFailed
        }
    }

    // Prompt strings are now managed by AIPromptProvider.
    // See Notiee/Services/AIPromptProvider.swift for all prompt definitions.
}

enum AIError: LocalizedError {
    case missingConfiguration
    case imageProcessingFailed
    case apiError(String)
    case parsingFailed

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "AI 模型尚未配置完整"
        case .imageProcessingFailed: return "图片处理失败"
        case .apiError(let msg): return "API 调用失败：\(msg)"
        case .parsingFailed: return "返回结果解析失败"
        }
    }
}
