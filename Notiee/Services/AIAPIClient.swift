import Foundation

enum OpenAICaller {
    static func callVision(endpoint: String, model: String, apiKey: String, base64Image: String, prompt: String) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 1500
        ]
        
        return try await performRequest(endpoint: endpoint, apiKey: apiKey, payload: payload)
    }

    static func callText(endpoint: String, model: String, apiKey: String, prompt: String) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 1000
        ]
        
        return try await performRequest(endpoint: endpoint, apiKey: apiKey, payload: payload)
    }
    
    private static func performRequest(endpoint: String, apiKey: String, payload: [String: Any]) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw AIError.apiError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.apiError("Unknown response")
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorString = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError("Status \(httpResponse.statusCode): \(errorString)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.parsingFailed
        }
        
        return content
    }
}

enum AnthropicCaller {
    static func callVision(endpoint: String, model: String, apiKey: String, base64Image: String, prompt: String) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1500,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]
        return try await performRequest(endpoint: endpoint, apiKey: apiKey, payload: payload)
    }

    static func callText(endpoint: String, model: String, apiKey: String, prompt: String) async throws -> String {
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1000,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        return try await performRequest(endpoint: endpoint, apiKey: apiKey, payload: payload)
    }
    
    private static func performRequest(endpoint: String, apiKey: String, payload: [String: Any]) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw AIError.apiError("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIError.apiError("Unknown response")
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let errorString = String(data: data, encoding: .utf8) ?? ""
            throw AIError.apiError("Status \(httpResponse.statusCode): \(errorString)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["content"] as? [[String: Any]],
              let firstContent = contents.first,
              let text = firstContent["text"] as? String else {
            throw AIError.parsingFailed
        }
        
        return text
    }
}
