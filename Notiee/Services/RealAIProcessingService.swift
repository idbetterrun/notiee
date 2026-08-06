import Foundation
import UIKit

// UserDefaults and Keychain are thread-safe; the injected store is treated as the same boundary.
struct RealAIProcessingService: AIProcessingService, @unchecked Sendable {
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
            if let data = Self.resizeAndCompress(image: image) {
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

    /// Resize + JPEG-compress for upload. `static` so the backend-backed service
    /// (`BackendAIProcessingService`) reuses the exact same encoding.
    static func resizeAndCompress(image: UIImage) -> Data? {
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

        let maxOCRChars = preset.visionStrategy == .fullVision ? 4000 : 6000
        let truncatedOCR = String(ocrText.prefix(maxOCRChars))

        let prompt = AIPromptProvider.textPrompt(
            ocrText: truncatedOCR,
            enableSummary: enableSummary,
            enableDetailedContent: enableDetailedContent,
            preset: preset
        )

        let responseJSON: String
        let tokens: Int
        if protocolType == .openai {
            let res = try await OpenAICaller.callText(endpoint: endpoint, model: config.modelName, apiKey: config.apiKey, systemPrompt: "", userPrompt: prompt)
            responseJSON = res.0
            tokens = res.1
        } else {
            let res = try await AnthropicCaller.callText(endpoint: endpoint, model: config.modelName, apiKey: config.apiKey, systemPrompt: "", userPrompt: prompt)
            responseJSON = res.0
            tokens = res.1
        }

        let result = try Self.parseStructuredNote(
            responseJSON: responseJSON,
            ocrText: ocrText,
            modelsUsed: [visionConfig.modelName, config.modelName]
        )
        return (result, tokens)
    }

    /// Parses the text model's structured-JSON reply into an `AIProcessingResult`.
    /// `static` + shared so both the BYOK (`RealAIProcessingService`) and the
    /// backend-backed (`BackendAIProcessingService`) paths decode identically.
    /// `tokenUsage` is left 0 for the caller to fill.
    static func parseStructuredNote(responseJSON: String, ocrText: String, modelsUsed: [String]) throws -> AIProcessingResult {
        let extractedJSON = extractJSONObject(from: responseJSON)

        guard let data = extractedJSON.data(using: .utf8) else {
            print("Failed to convert cleaned JSON to data. Raw: \(String(responseJSON.prefix(200)))")
            throw AIError.parsingFailed
        }

        // 所有字段都做容错：模型输出格式非确定性，任何单个字段的形态波动
        // 都不能拖垮整份有效笔记。缺失/类型不符一律降级为安全默认值。
        struct ParsedOutput: Decodable {
            let title: String?
            let summary: String?
            let detailedContent: String?
            let todos: LenientStringArray?
            let keyPoints: LenientStringArray?
            let definitions: LenientDefinitions?
        }

        do {
            let parsed = try JSONDecoder().decode(ParsedOutput.self, from: data)
            return AIProcessingResult(
                title: parsed.title?.nonEmpty ?? "无标题",
                ocrText: ocrText,
                summary: parsed.summary ?? "",
                detailedContent: parsed.detailedContent?.nonEmpty ?? "无详细内容",
                todos: parsed.todos?.values ?? [],
                keyPoints: parsed.keyPoints?.values ?? [],
                definitions: (parsed.definitions?.values ?? [])
                    .filter { !$0.term.isEmpty }
                    .map { KeyDefinition(term: $0.term, explanation: $0.explanation) },
                modelsUsed: modelsUsed,
                tokenUsage: 0
            )
        } catch {
            print("Failed to decode JSON: \(error). Cleaned JSON: \(String(extractedJSON.prefix(300)))")
            throw AIError.parsingFailed
        }
    }

    // MARK: - Lenient decoding helpers
    //
    // 模型返回的 JSON 字段形态不稳定（同一字段可能是数组/字典/字符串，或干脆缺失）。
    // 这些包装类型吸收所有已知与未知形态，解不出就退化为空，绝不抛错——
    // 保证只要顶层 JSON 能解析，笔记就能落地，不因某个次要字段浪费整次 token。

    /// 术语解释。接受 {term, explanation} 对象、"术语：解释" 字符串两种元素形态。
    struct ParsedDefinition: Decodable {
        let term: String
        let explanation: String

        init(term: String, explanation: String) {
            self.term = term
            self.explanation = explanation
        }

        init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let raw = try? single.decode(String.self) {
                let separators: [Character] = ["：", ":", "—", "-"]
                if let idx = raw.firstIndex(where: { separators.contains($0) }) {
                    term = String(raw[..<idx]).trimmingCharacters(in: .whitespaces)
                    explanation = String(raw[raw.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                } else {
                    term = raw.trimmingCharacters(in: .whitespaces)
                    explanation = ""
                }
                return
            }
            let obj = try decoder.container(keyedBy: CodingKeys.self)
            term = try obj.decode(String.self, forKey: .term)
            explanation = (try? obj.decode(String.self, forKey: .explanation)) ?? ""
        }

        enum CodingKeys: String, CodingKey { case term, explanation }
    }

    /// definitions 字段整体容错：接受对象数组、字符串数组、
    /// 字典 {"术语":"解释"}，或任意无法识别的形态（→ 空）。
    struct LenientDefinitions: Decodable {
        let values: [ParsedDefinition]

        init(from decoder: Decoder) throws {
            // 形态 1：数组（元素为对象或字符串，逐个容错，跳过坏元素）
            if var arr = try? decoder.unkeyedContainer() {
                var out: [ParsedDefinition] = []
                while !arr.isAtEnd {
                    if let d = try? arr.decode(ParsedDefinition.self) {
                        out.append(d)
                    } else {
                        _ = try? arr.decode(AnyCodable.self) // 消费掉坏元素继续
                    }
                }
                values = out
                return
            }
            // 形态 2：字典 {"术语":"解释", ...}
            if let dict = try? decoder.singleValueContainer().decode([String: String].self) {
                values = dict.map { ParsedDefinition(term: $0.key, explanation: $0.value) }
                return
            }
            // 形态 3：无法识别 → 空，绝不抛错
            values = []
        }
    }

    /// todos / keyPoints 字段容错：接受字符串数组，或单个字符串，或其他形态（→ 空）。
    struct LenientStringArray: Decodable {
        let values: [String]

        init(from decoder: Decoder) throws {
            if var arr = try? decoder.unkeyedContainer() {
                var out: [String] = []
                while !arr.isAtEnd {
                    if let s = try? arr.decode(String.self) {
                        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { out.append(t) }
                    } else {
                        _ = try? arr.decode(AnyCodable.self)
                    }
                }
                values = out
                return
            }
            if let single = try? decoder.singleValueContainer(),
               let s = try? single.decode(String.self) {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                values = t.isEmpty ? [] : [t]
                return
            }
            values = []
        }
    }

    /// 用于安全消费并丢弃任意 JSON 值。
    private struct AnyCodable: Decodable {
        init(from decoder: Decoder) throws {
            if let c = try? decoder.singleValueContainer(), c.decodeNil() { return }
            if var u = try? decoder.unkeyedContainer() {
                while !u.isAtEnd { _ = try? u.decode(AnyCodable.self) }
                return
            }
            if let k = try? decoder.container(keyedBy: AnyKey.self) {
                for key in k.allKeys { _ = try? k.decode(AnyCodable.self, forKey: key) }
            }
        }
        struct AnyKey: CodingKey {
            var stringValue: String; var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
            init?(intValue: Int) { self.intValue = intValue; stringValue = String(intValue) }
        }
    }

    static func extractJSONObject(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: "```json") {
            cleaned = String(cleaned[range.upperBound...])
        } else if let range = cleaned.range(of: "```") {
            cleaned = String(cleaned[range.upperBound...])
        }
        if let range = cleaned.range(of: "```", options: .backwards) {
            cleaned = String(cleaned[..<range.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startIdx = cleaned.firstIndex(of: "{"),
              let endIdx = cleaned.lastIndex(of: "}") else {
            return cleaned
        }
        return String(cleaned[startIdx...endIdx])
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

fileprivate extension String {
    /// 去除首尾空白后为空则返回 nil，便于用 `?? 默认值` 兜底。
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
