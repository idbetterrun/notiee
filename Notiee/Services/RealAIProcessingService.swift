import Foundation
import UIKit

struct RealAIProcessingService: AIProcessingService {
    let settingsStore: AppSettingsPersisting

    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        self.settingsStore = settingsStore
    }

    func process(imagePath: String, eventTitle: String?) async throws -> AIProcessingResult {
        let textConfig = settingsStore.loadConfiguration(for: .text)
        let visionConfig = settingsStore.loadConfiguration(for: .vision)

        guard textConfig.isComplete, visionConfig.isComplete else {
            throw AIError.missingConfiguration
        }

        // 1. Process image
        let base64Image = try await processImage(from: imagePath)
        
        // 2. Call Vision model for OCR
        let ocrText = try await callVisionModel(config: visionConfig, base64Image: base64Image)
        
        // 3. Call Text model for JSON summary
        let result = try await callTextModel(config: textConfig, ocrText: ocrText, eventTitle: eventTitle)
        
        return result
    }

    private func processImage(from path: String) async throws -> String {
        guard let image = await MainActor.run(body: { LocalImageStore.shared.loadImage(path: path) }) else {
            throw AIError.imageProcessingFailed
        }
        
        // Resize to max 1024
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
        
        guard let jpegData = resizedImage.jpegData(compressionQuality: 0.6) else {
            throw AIError.imageProcessingFailed
        }
        
        return jpegData.base64EncodedString()
    }

    private func callVisionModel(config: AIModelConfiguration, base64Image: String) async throws -> String {
        let endpoint = config.activeEndpoint
        let protocolType = config.activeProtocol
        
        let prompt = "请识别图片中的所有文本内容，包含板书、幻灯片等，并尽可能保持原本的结构输出。除了文本内容外，如果有关键的图表或公式也可以用文字简单描述一下。不要输出任何除了提取内容以外的废话。"
        
        if protocolType == .openai {
            return try await OpenAICaller.callVision(endpoint: endpoint, model: config.modelName, apiKey: config.apiKey, base64Image: base64Image, prompt: prompt)
        } else {
            return try await AnthropicCaller.callVision(endpoint: endpoint, model: config.modelName, apiKey: config.apiKey, base64Image: base64Image, prompt: prompt)
        }
    }

    private func callTextModel(config: AIModelConfiguration, ocrText: String, eventTitle: String?) async throws -> AIProcessingResult {
        let endpoint = config.activeEndpoint
        let protocolType = config.activeProtocol
        
        let context = eventTitle != nil ? "当前所处的日程为：\(eventTitle!)" : "当前无关联日程"
        
        let prompt = """
        你是一个课堂/会议笔记助理。请根据以下 OCR 提取的内容和上下文，生成一份结构化的摘要。
        上下文：\(context)
        OCR 内容：
        \(ocrText)
        
        请严格以 JSON 格式输出，包含以下字段：
        - "title": (String) 笔记的标题（不要太长）
        - "summary": (String) 内容摘要，概括核心要点
        - "todos": (Array of String) 提取出的可能需要执行的行动项或待办（如果没有请返回空数组）
        
        注意：必须返回合法的 JSON 对象，不要包含 markdown 代码块如 ```json 等，确保可以直接解析。
        """
        
        let responseJSON: String
        if protocolType == .openai {
            responseJSON = try await OpenAICaller.callText(endpoint: endpoint, model: config.modelName, apiKey: config.apiKey, prompt: prompt)
        } else {
            responseJSON = try await AnthropicCaller.callText(endpoint: endpoint, model: config.modelName, apiKey: config.apiKey, prompt: prompt)
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
            let todos: [String]
        }
        
        do {
            let parsed = try JSONDecoder().decode(ParsedOutput.self, from: data)
            return AIProcessingResult(title: parsed.title, ocrText: ocrText, summary: parsed.summary, todos: parsed.todos)
        } catch {
            print("Failed to decode JSON: \(error)")
            throw AIError.parsingFailed
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
