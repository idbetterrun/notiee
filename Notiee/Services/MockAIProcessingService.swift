import Foundation

/// AI 处理管线的 Mock 占位服务。
///
/// 拍照后，该服务模拟异步延迟并返回预设的 OCR 文本、摘要、小标题和待办事项，
/// 使主流程在尚未接入真实大模型 API 之前即可完整走通。
/// 后续接入真实 Vision / Text LLM 时，只需替换此服务的实现。
struct MockAIProcessingService: AIProcessingService {

    /// 模拟 AI 处理的延迟区间（秒）。
    var processingDelay: ClosedRange<Double>

    init(processingDelay: ClosedRange<Double> = 2.0...4.0) {
        self.processingDelay = processingDelay
    }

    /// 根据关联的日程标题生成 Mock AI 结果。
    ///
    /// - Parameter eventTitle: 当前绑定的日程名称，用于选取对口的 Mock 数据。
    ///   传入 nil 表示未分类拍记。
    /// - Returns: 一组模拟的 OCR、摘要、小标题和待办事项。
    func process(imagePaths: [String], eventTitle: String?) async throws -> AIProcessingResult {
        // Simulate network delay
        try await Task.sleep(nanoseconds: 2_000_000_000)
        
        let shouldFail = imagePaths.first?.contains("fail") ?? false
        if shouldFail {
            throw NSError(domain: "MockAI", code: 500, userInfo: [NSLocalizedDescriptionKey: "模拟的 AI 处理失败"])
        }

        // 尝试按关键字匹配一条上下文相关的 Mock 数据
        if let eventTitle {
            for entry in Self.pool {
                for keyword in entry.keywords {
                    if eventTitle.localizedCaseInsensitiveContains(keyword) {
                        return entry.result
                    }
                }
            }
        }

        // 未命中任何关键词时，随机选取一条
        return Self.pool.randomElement()?.result ?? Self.fallback
    }

    // MARK: - Mock Data Pool

    private struct TaggedResult {
        let keywords: [String]
        let result: AIProcessingResult
    }

    private static let pool: [TaggedResult] = [
        TaggedResult(
            keywords: ["数学", "高数", "微积分", "线代"],
            result: AIProcessingResult(
                title: "极限与连续性",
                ocrText: """
                定义 2.1  函数极限的 ε-δ 定义
                ∀ε > 0, ∃δ > 0, 当 0 < |x - x₀| < δ 时, |f(x) - A| < ε
                推论: 极限唯一性定理
                导数定义: f'(x₀) = lim[Δx→0] (f(x₀+Δx) - f(x₀)) / Δx
                ∫₀¹ x² dx = 1/3
                """,
                summary: "这是一段由本地 Mock 服务生成的测试摘要。该系统仅用于开发与调试阶段。",
                detailedContent: "这是由 Mock 服务生成的超长详细内容。它的存在是为了在无需消耗真实 API 费用的情况下，验证我们的长文本显示、滚动以及复制功能是否一切正常。这段文字非常非常非常长，应该能够跨越多行。",
                todos: [
                    "完成 UI 原型设计",
                    "实现 Mock 数据绑定",
                    "修复深色模式样式问题"
                ],
                modelsUsed: ["Mock Vision Model", "Mock Text Model"],
                tokenUsage: 1250
            )
        ),
        TaggedResult(
            keywords: ["设计", "产品", "UI", "UX", "交互"],
            result: AIProcessingResult(
                title: "用户旅程与交互原型",
                ocrText: """
                用户旅程图 (User Journey Map)
                1. 触发点 → 2. 首次体验 → 3. 核心行为 → 4. 留存钩子
                信息架构：卡片排序法 (Card Sorting)
                Figma 组件化设计系统：Color Token, Typography Scale
                """,
                summary: "课堂整理了用户旅程图的四阶段模型，介绍了卡片排序法确定信息架构，并演示了 Figma 组件化设计系统的搭建方式。",
                detailedContent: "详细内容：在这节设计课中，黑板上绘制了完整的四阶段漏斗模型，并且分析了每个阶段流失率的阈值，建议重点关注首次体验的 A/B 测试。",
                todos: ["绘制 Notiee 的用户旅程图初稿", "整理竞品截图到设计文档"],
                modelsUsed: ["Mock Vision Model v1", "Mock Text Model v1"],
                tokenUsage: 980
            )
        ),
        TaggedResult(
            keywords: ["项目", "讨论", "会议", "周会", "站会"],
            result: AIProcessingResult(
                title: "项目进度与分工确认",
                ocrText: """
                Sprint 回顾：已完成 12/15 个 Story Point
                遗留问题：API 超时重试策略待定
                下周目标：完成相机模块集成与 AI 管线对接
                负责人：@小谭 - iOS 端, @小李 - 后端
                """,
                summary: "本次会议回顾了 Sprint 完成情况（80%），讨论了 API 超时的重试策略，并明确了下周的模块分工与集成目标。",
                detailedContent: "详细内容：本次会议纪要总结了 Sprint 的开发进度，并指出了目前存在的 API 超时问题，明确了小谭和小李在下周的开发任务。",
                todos: ["制定 API 超时的指数退避重试方案", "下周三前完成相机模块集成"],
                modelsUsed: ["Mock Vision Model v1", "Mock Text Model v1"],
                tokenUsage: 760
            )
        ),
        TaggedResult(
            keywords: ["英语", "English", "语言"],
            result: AIProcessingResult(
                title: "学术写作结构",
                ocrText: """
                Academic Essay Structure
                1. Introduction – Thesis Statement
                2. Body Paragraphs – Topic Sentence + Evidence + Analysis
                3. Conclusion – Restate & Implications
                Transition words: However, Furthermore, In contrast, Consequently
                """,
                summary: "本节课讲解了学术论文的三段式结构（引言、正文、结论），以及常用过渡词的使用场景。",
                detailedContent: "详细内容：学术写作的逻辑结构分析，涵盖了从论文陈述到正文论证及结论总结的各个环节，并列举了关键的衔接词。",
                todos: ["用三段式结构改写上周的作文草稿"],
                modelsUsed: ["Mock Vision Model v1", "Mock Text Model v1"],
                tokenUsage: 1100
            )
        ),
        TaggedResult(
            keywords: ["物理", "力学", "电磁"],
            result: AIProcessingResult(
                title: "牛顿运动定律应用",
                ocrText: """
                牛顿第二定律: F = ma
                自由体受力图 (Free Body Diagram)
                摩擦力: f = μN
                示例: 斜面上物体的加速度 a = g(sinθ - μcosθ)
                """,
                summary: "本节课通过自由体受力图分析了牛顿第二定律在斜面运动中的应用，推导了含摩擦力情况下的加速度公式。",
                detailedContent: "详细内容：本节课深入探讨了受力分析的基本法则，通过自由体受力图详细拆解了斜面物体的受力情况并推导了运动公式。",
                todos: ["完成斜面运动习题 4.3 - 4.7", "画出三种典型场景的受力图"],
                modelsUsed: ["Mock Vision Model v1", "Mock Text Model v1"],
                tokenUsage: 1420
            )
        ),
    ]

    private static let fallback = AIProcessingResult(
        title: "课堂笔记摘要",
        ocrText: """
        重点概念梳理
        1. 核心定义与基本原理
        2. 典型例题与解题思路
        3. 课后延伸阅读材料
        板书备注：下周测验范围为第 3-5 章
        """,
        summary: "本次课堂整理了核心定义与基本原理，通过典型例题演示了解题思路，并提示下周测验范围为第 3-5 章。",
        detailedContent: "这是一段用于默认占位的详细内容，描述了该图片或笔记可能涉及的主要信息和细节。",
        todos: ["复习第 3-5 章核心概念", "整理本次课堂例题到笔记本"],
        modelsUsed: ["Mock Vision Model v1", "Mock Text Model v1"],
        tokenUsage: 888
    )
}
