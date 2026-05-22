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

        guard textConfig.isComplete, visionConfig.isComplete else {
            throw AIError.missingConfiguration
        }

        // 1. Process all images
        var base64Images: [String] = []
        for path in imagePaths {
            guard let image = await MainActor.run(body: { LocalImageStore.shared.loadImage(path: path) }) else { continue }
            if let data = resizeAndCompress(image: image) {
                base64Images.append(data.base64EncodedString())
            }
        }
        
        guard !base64Images.isEmpty else {
            throw AIError.imageProcessingFailed
        }
        
        // 2. Call Vision model for OCR (sending multiple images)
        let (ocrText, visionTokens) = try await callVisionModel(config: visionConfig, base64Images: base64Images)
        
        // 3. Call Text model for JSON summary
        let (result, textTokens) = try await callTextModel(config: textConfig, visionConfig: visionConfig, ocrText: ocrText, eventTitle: eventTitle)
        
        return AIProcessingResult(
            title: result.title,
            ocrText: result.ocrText,
            summary: result.summary,
            detailedContent: result.detailedContent,
            todos: result.todos,
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

    private func callVisionModel(config: AIModelConfiguration, base64Images: [String]) async throws -> (String, Int) {
        let endpoint = config.activeEndpoint
        let protocolType = config.activeProtocol
        
        let prompt = Self.localizedVisionPrompt()
        
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
                "content": Self.localizedVisionSystemPrompt()
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
        
        // This is a bit of a hack since OpenAICaller.callVision only took single image before,
        // we will manually call HTTP here to support multi-image array in the prompt.
        
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

    private func callTextModel(config: AIModelConfiguration, visionConfig: AIModelConfiguration, ocrText: String, eventTitle: String?) async throws -> (AIProcessingResult, Int) {
        let endpoint = config.activeEndpoint
        let protocolType = config.activeProtocol
        
        let enableSummary = settingsStore.loadBool(forKey: "notiee.aiEnableSummary", defaultValue: true)
        let enableDetailedContent = settingsStore.loadBool(forKey: "notiee.aiEnableDetailedContent", defaultValue: true)
        let enableTodos = settingsStore.loadBool(forKey: "notiee.aiEnableTodos", defaultValue: true)
        
        let prompt = Self.localizedTextPrompt(
            ocrText: ocrText,
            enableSummary: enableSummary,
            enableDetailedContent: enableDetailedContent,
            enableTodos: enableTodos
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
        
        // Clean markdown backticks if any
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
        }
        
        do {
            let parsed = try JSONDecoder().decode(ParsedOutput.self, from: data)
            let result = AIProcessingResult(
                title: parsed.title,
                ocrText: ocrText,
                summary: parsed.summary,
                detailedContent: parsed.detailedContent ?? "无详细内容",
                todos: parsed.todos,
                modelsUsed: [visionConfig.modelName, config.modelName],
                tokenUsage: 0
            )
            return (result, tokens)
        } catch {
            print("Failed to decode JSON: \(error)")
            throw AIError.parsingFailed
        }
    }
    
    // MARK: - Localized Prompts
    
    static func currentLanguage() -> String {
        return UserDefaults.standard.string(forKey: "notiee.language") ?? "system"
    }
    
    static func localizedVisionPrompt() -> String {
        let lang = currentLanguage()
        if lang == "en" {
            return "Please recognize all text content in the images, including blackboard writing, presentation slides, etc., and maintain the original layout structure as much as possible. Multiple images are coherent, please extract comprehensively. In addition to text content, if there are key charts or formulas, briefly describe them with text. Do not output any nonsense other than the extracted content."
        } else if lang == "zh-Hant" {
            return "請識別圖片中的所有文本內容，包含板書、幻燈片等，並儘可能保持原本的結構輸出。多張圖片是連貫的，請綜合提取。除了文本內容外，如果有關鍵的圖表或公式也可以用文字簡單描述一下。不要輸出任何除了提取內容以外的廢話。"
        } else {
            return "请识别图片中的所有文本内容，包含板书、幻灯片等，并尽可能保持原本的结构输出。多张图片是连贯的，请综合提取。除了文本内容外，如果有关键的图表或公式也可以用文字简单描述一下。不要输出任何除了提取内容以外的废话。"
        }
    }
    
    static func localizedVisionSystemPrompt() -> String {
        let lang = currentLanguage()
        if lang == "en" {
            return "You are a class note organizing assistant. Please analyze the provided images (which may be consecutive blackboard writings or slides), extract text, summarize the outline, and identify all tasks or action items. Multiple images are taken chronologically, please consider their contents comprehensively. Output in JSON format."
        } else if lang == "zh-Hant" {
            return "你是一個課堂筆記整理助手。請分析提供的圖片（可能是連續多張板書/幻燈片），提取文字，總結大綱，並識別出所有任務或待辦事項。多張圖片是按時間順序拍攝的，請綜合考慮它們的內容。以 JSON 格式輸出。"
        } else {
            return "你是一个课堂笔记整理助手。请分析提供的图片（可能是连续多张板书/幻灯片），提取文字，总结大纲，并识别出所有任务或待办事项。多张图片是按时间顺序拍摄的，请综合考虑它们的内容。以 JSON 格式输出。"
        }
    }
    
    static func localizedTextPrompt(ocrText: String, enableSummary: Bool, enableDetailedContent: Bool, enableTodos: Bool) -> String {
        let lang = currentLanguage()
        if lang == "en" {
            return """
            Please carefully analyze the following text extracted from images.

            Based on the requirements below, return a strictly formatted JSON object. Do not return any other content (no Markdown code blocks, no explanations).

            Fields to extract:
            1. "title": Generate a short title based on the content (under 10 words).
            \(enableSummary ? "2. \"summary\": Extract a brief summary of the content (under 100 words)." : "")
            \(enableDetailedContent ? "3. \"detailedContent\": Reformat the provided OCR text, fix typos, and organize it into coherent, readable detailed content (if it's class notes or meeting minutes, use paragraphs and bullet points for core takeaways). If output is in English, keep it under 2500 characters." : "")
            \(enableTodos ? "4. \"todos\": If the text contains any tasks or action items to execute, extract them as an array of strings (if none, return an empty array [])." : "")

            Here is the extracted text content:
            \(ocrText)
            """
        } else if lang == "zh-Hant" {
            return """
            請仔細分析以下提取自圖片的文字內容。

            根據以下要求，返回一個嚴格格式化的 JSON 對象。不要返回任何其他內容（不要帶 Markdown 代碼塊，不要有解釋說明）。

            需要提取的字段：
            1. "title": 根據內容生成一個簡短的標題（不要超過15個字）。
            \(enableSummary ? "2. \"summary\": 提取出簡短的內容摘要（控制在200字以內）。" : "")
            \(enableDetailedContent ? "3. \"detailedContent\": 將提供的 OCR 文本重新排版，修正錯別字，梳理成連貫且易於閱讀的詳細內容（如果是課堂筆記或會議記錄，請分段落、列出核心要點）。注意：最長不要超過 500 字。" : "")
            \(enableTodos ? "4. \"todos\": 如果文本中包含任何需要執行的任務或待辦事項，請提取為一個字符串數組（如果沒有，則返回空數組 []）。" : "")

            以下是提取的文字內容：
            \(ocrText)
            """
        } else {
            return """
            请仔细分析以下提取自图片的文字内容。

            根据以下要求，返回一个严格格式化的 JSON 对象。不要返回任何其他内容（不要带 Markdown 代码块，不要有解释说明）。

            需要提取的字段：
            1. "title": 根据内容生成一个简短的标题（不要超过15个字）。
            \(enableSummary ? "2. \"summary\": 提取出简短的内容摘要（控制在200字以内）。" : "")
            \(enableDetailedContent ? "3. \"detailedContent\": 将提供的 OCR 文本重新排版，修正错别字，梳理成连贯且易于阅读的详细内容（如果是课堂笔记或会议记录，请分段落、列出核心要点）。注意：最长不要超过 500 字。" : "")
            \(enableTodos ? "4. \"todos\": 如果文本中包含任何需要执行的任务或待办事项，请提取为一个字符串数组（如果没有，则返回空数组 []）。" : "")

            以下是提取的文字内容：
            \(ocrText)
            """
        }
    }
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
