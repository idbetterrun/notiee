import Foundation

enum AIModelKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case text
    case vision

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .text:
            "文本处理模型"
        case .vision:
            "图像识别模型"
        }
    }

    var readyMessage: String {
        switch self {
        case .text:
            "文本处理模型配置可用。"
        case .vision:
            "图像识别模型配置可用。"
        }
    }
}

struct AIModelConfiguration: Equatable, Codable, Sendable {
    var providerType: AIProviderType
    var customEndpoint: String
    var customProtocol: AIProtocol
    var modelName: String
    var apiKey: String

    init(
        providerType: AIProviderType,
        customEndpoint: String = "",
        customProtocol: AIProtocol = .openai,
        modelName: String = "",
        apiKey: String = ""
    ) {
        self.providerType = providerType
        self.customEndpoint = customEndpoint
        self.customProtocol = customProtocol
        self.modelName = modelName
        self.apiKey = apiKey
    }

    var isComplete: Bool {
        if providerType == .custom {
            return !customEndpoint.trimmed.isEmpty
                && !modelName.trimmed.isEmpty
                && !apiKey.trimmed.isEmpty
        } else {
            return !modelName.trimmed.isEmpty
                && !apiKey.trimmed.isEmpty
        }
    }
    
    var activeEndpoint: String {
        providerType == .custom ? customEndpoint : providerType.endpoint
    }
    
    var activeProtocol: AIProtocol {
        providerType == .custom ? customProtocol : providerType.protocolType
    }

    var normalized: AIModelConfiguration {
        AIModelConfiguration(
            providerType: providerType,
            customEndpoint: customEndpoint.trimmed,
            customProtocol: customProtocol,
            modelName: modelName.trimmed,
            apiKey: apiKey.trimmed
        )
    }
    
    // Custom decoding to prevent crash from old schema
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.providerType = try container.decodeIfPresent(AIProviderType.self, forKey: .providerType) ?? .qwenText
        self.customEndpoint = try container.decodeIfPresent(String.self, forKey: .customEndpoint) ?? ""
        self.customProtocol = try container.decodeIfPresent(AIProtocol.self, forKey: .customProtocol) ?? .openai
        self.modelName = try container.decodeIfPresent(String.self, forKey: .modelName) ?? ""
        self.apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
    }
}

enum AIConnectionTestStatus: Equatable, Sendable {
    case idle
    case success(String)
    case failure(String)
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
