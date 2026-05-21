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
    var providerName: String
    var endpoint: String
    var modelName: String
    var apiKey: String

    init(
        providerName: String = "OpenAI Compatible",
        endpoint: String = "",
        modelName: String = "",
        apiKey: String = ""
    ) {
        self.providerName = providerName
        self.endpoint = endpoint
        self.modelName = modelName
        self.apiKey = apiKey
    }

    var isComplete: Bool {
        !providerName.trimmed.isEmpty
            && !endpoint.trimmed.isEmpty
            && !modelName.trimmed.isEmpty
            && !apiKey.trimmed.isEmpty
    }

    var normalized: AIModelConfiguration {
        AIModelConfiguration(
            providerName: providerName.trimmed,
            endpoint: endpoint.trimmed,
            modelName: modelName.trimmed,
            apiKey: apiKey.trimmed
        )
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
