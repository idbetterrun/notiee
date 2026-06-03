import Foundation

enum SparkAIError: LocalizedError {
    case missingConfiguration
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration: return "AI 模型尚未配置"
        case .apiError(let msg): return "AI 调用失败：\(msg)"
        }
    }
}

final class SparkAIService: Sendable {
    private let settingsStore: AppSettingsPersisting
    private let memoryStore: SparkMemoryPersisting
    private let maxRecordsInPrompt = 150

    init(
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live,
        memoryStore: SparkMemoryPersisting = SparkMemoryStore.live
    ) {
        self.settingsStore = settingsStore
        self.memoryStore = memoryStore
    }

    func askStreaming(question: String, with allRecords: [NoteRecord]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let textConfig = settingsStore.loadConfiguration(for: .text)
                guard textConfig.isComplete else {
                    continuation.finish(throwing: SparkAIError.missingConfiguration)
                    return
                }
                let activeRecords = allRecords
                    .filter { !$0.isDeleted }
                    .sorted { $0.capturedAt > $1.capturedAt }
                    .prefix(maxRecordsInPrompt)
                let prompt = buildPrompt(question: question, records: Array(activeRecords))

                let stream: AsyncThrowingStream<String, Error>
                if textConfig.activeProtocol == .openai {
                    stream = OpenAICaller.streamText(
                        endpoint: textConfig.activeEndpoint, model: textConfig.modelName,
                        apiKey: textConfig.apiKey, prompt: prompt, temperature: 0.95)
                } else {
                    stream = AnthropicCaller.streamText(
                        endpoint: textConfig.activeEndpoint, model: textConfig.modelName,
                        apiKey: textConfig.apiKey, prompt: prompt, temperature: 0.95)
                }
                do {
                    for try await chunk in stream { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func extractMemory(from text: String) -> (cleanText: String, newMemories: [String: String]) {
        let pattern = "\\[记忆\\](.*?)\\[/记忆\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return (text, [:])
        }
        var clean = text; var memories: [String: String] = [:]
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            if let range = Range(match.range, in: text),
               let cRange = Range(match.range(at: 1), in: text) {
                let content = String(text[cRange]).trimmingCharacters(in: .whitespaces)
                let parts = content.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = String(parts[0].trimmingCharacters(in: .whitespaces).prefix(50))
                    let value = String(parts[1].trimmingCharacters(in: .whitespaces).prefix(50))
                    memories[key] = value
                }
                clean.removeSubrange(range)
            }
        }
        return (clean.trimmingCharacters(in: .whitespacesAndNewlines), memories)
    }

    func extractCitations(from text: String, recordCount: Int) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: "\\[来源(\\d+)\\]") else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var indices = Set<Int>()
        for m in matches {
            if let r = Range(m.range(at: 1), in: text), let idx = Int(text[r]), idx >= 1, idx <= recordCount {
                indices.insert(idx - 1)
            }
        }
        return Array(indices).sorted()
    }

    private func buildPrompt(question: String, records: [NoteRecord]) -> String {
        let mem = (try? memoryStore.load()) ?? [:]
        let memLines: String
        if mem.isEmpty {
            memLines = "（暂无记忆）"
        } else {
            memLines = "关于你，我目前记得：\n" + mem.map { "  - \($0.key): \($0.value)" }.joined(separator: "\n")
        }

        var rb = ""
        for (i, r) in records.enumerated() {
            let d = r.capturedAt.formatted(date: .abbreviated, time: .shortened)
            let s = r.summary.isEmpty ? "" : "摘要：\(trunc(r.summary, 100))"
            rb += "[记录\(i+1)] \(r.title) | \(d)\n\(s)\n"
        }

        return """
        你是 Spark，Notiee 里的个人 AI 伴侣。
        你不是客服机器人——你是一个善于倾听、有好奇心、偶尔会俏皮、能记住关于用户的事情的朋友。

        你的性格：
        - 温暖但不油腻。回应自然，像人类朋友聊天。
        - 聪明但不刻意卖弄。不提用户没问的知识。
        - 幽默但知道分寸。尊重中国文化和社会伦理。
        - 诚实但不冷漠。即使用户记录帮不上忙，也用友好的方式回应，不是丢一句「未找到」就结束。
        - 记住用户的事。如果用户告诉你 TA 的名字、喜好、最近状态，下次聊到时自然提起。

        你的工作方式：
        - 用户和你聊天时，你的回答会基于以下「记忆」和「拍记记录」。
        - 如果用户没有问拍记相关的事，就自然聊天，不必强行引用记录。
        - 如果你想记住用户的新信息（名字、偏好、习惯等），在回答中用 [记忆]键:值[/记忆] 的格式悄悄记下来（这对用户不可见）。
        - 引用记录时用 [来源N] 标记。

        当前记忆：
        \(memLines)

        当前共有 \(records.count) 条拍记：
        \(rb)

        用户说：\(question)
        """
    }

    private func trunc(_ text: String, _ max: Int) -> String {
        text.count <= max ? text : String(text.prefix(max)) + "..."
    }
}
