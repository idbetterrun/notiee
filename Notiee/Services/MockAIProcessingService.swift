import Foundation

struct MockAIProcessingService: AIProcessingService {

    var processingDelay: ClosedRange<Double>

    init(processingDelay: ClosedRange<Double> = 2.0...4.0) {
        self.processingDelay = processingDelay
    }

    func process(imagePaths: [String], eventTitle: String?) async throws -> AIProcessingResult {
        let delay = Double.random(in: processingDelay)
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        let shouldFail = imagePaths.first?.contains("fail") ?? false
        if shouldFail {
            throw NSError(domain: "MockAI", code: 500, userInfo: [NSLocalizedDescriptionKey: "模拟的 AI 处理失败"])
        }

        return AIProcessingResult(
            title: "课堂笔记摘要",
            ocrText: """
            重点概念梳理
            1. 核心定义与基本原理
            2. 典型例题与解题思路
            3. 课后延伸阅读材料
            """,
            summary: "本次课堂整理了核心定义与基本原理，通过典型例题演示了解题思路。",
            detailedContent: "这是一段用于开发调试的详细内容，描述了图片或笔记可能涉及的主要信息和细节。",
            todos: ["整理本次课堂笔记", "完成课后练习"],
            keyPoints: ["核心定义", "基本原理", "解题思路"],
            definitions: [
                KeyDefinition(term: "核心概念", explanation: "本文讨论的基本定义")
            ],
            modelsUsed: ["Mock Vision Model", "Mock Text Model"],
            tokenUsage: 0
        )
    }
}
