import Foundation

enum AIProtocol: String, Codable, Sendable, CaseIterable, Identifiable {
    case openai
    case anthropic
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .openai: "OpenAI 兼容"
        case .anthropic: "Anthropic 兼容"
        }
    }
}

enum AIProviderType: String, Codable, Sendable, CaseIterable, Identifiable {
    // Text Providers
    case qwenText
    case doubaoText
    case deepseek
    case minimax
    
    // Vision Providers
    case qwenVision
    case doubaoVision
    
    // Custom Providers
    case custom
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .qwenText: "阿里通义千问"
        case .doubaoText: "火山引擎豆包"
        case .deepseek: "DeepSeek"
        case .minimax: "MiniMax"
        case .qwenVision: "通义千问视觉 (Qwen VL)"
        case .doubaoVision: "豆包视觉 (Doubao Vision)"
        case .custom: "自定义模型"
        }
    }
    
    var endpoint: String {
        switch self {
        case .qwenText, .qwenVision:
            return "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .doubaoText, .doubaoVision:
            return "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        case .deepseek:
            return "https://api.deepseek.com/chat/completions"
        case .minimax:
            return "https://api.minimax.chat/v1/chat/completions"
        case .custom:
            return ""
        }
    }
    
    var protocolType: AIProtocol {
        // Predefined providers currently all use OpenAI format
        return .openai
    }
    
    var predefinedModels: [String] {
        switch self {
        case .qwenText:
            return ["qwen-plus", "qwen-turbo", "qwen-max"]
        case .qwenVision:
            return ["qwen-vl-plus", "qwen-vl-max"]
        case .deepseek:
            return ["deepseek-chat"]
        case .minimax:
            return ["abab6.5s-chat"]
        default:
            return []
        }
    }
    
    var isEndpointIdRequired: Bool {
        switch self {
        case .doubaoText, .doubaoVision:
            return true
        default:
            return false
        }
    }
}
