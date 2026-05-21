import Foundation

/// AI 处理管线的 Mock 占位服务。
///
/// 拍照后，该服务模拟异步延迟并返回预设的 OCR 文本、摘要、小标题和待办事项，
/// 使主流程在尚未接入真实大模型 API 之前即可完整走通。
/// 后续接入真实 Vision / Text LLM 时，只需替换此服务的实现。
struct MockAIProcessingService: Sendable {

    /// 模拟 AI 处理后的结构化结果。
    struct Result: Sendable {
        let title: String
        let ocrText: String
        let summary: String
        let todos: [String]
    }

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
    func generate(for eventTitle: String?) -> Result {
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
        let result: Result
    }

    private static let pool: [TaggedResult] = [
        TaggedResult(
            keywords: ["数学", "高数", "微积分", "线代"],
            result: Result(
                title: "极限与连续性",
                ocrText: """
                定义 2.1  函数极限的 ε-δ 定义
                ∀ε > 0, ∃δ > 0, 当 0 < |x - x₀| < δ 时, |f(x) - A| < ε
                推论: 极限唯一性定理
                导数定义: f'(x₀) = lim[Δx→0] (f(x₀+Δx) - f(x₀)) / Δx
                ∫₀¹ x² dx = 1/3
                """,
                summary: "本节课讲解了函数极限的 ε-δ 严格定义及其唯一性定理，并引入导数的极限定义与基本积分公式。",
                todos: ["复习 ε-δ 定义的三步证明法", "完成课本第三章习题 3.1 - 3.8"]
            )
        ),
        TaggedResult(
            keywords: ["设计", "产品", "UI", "UX", "交互"],
            result: Result(
                title: "用户旅程与交互原型",
                ocrText: """
                用户旅程图 (User Journey Map)
                1. 触发点 → 2. 首次体验 → 3. 核心行为 → 4. 留存钩子
                信息架构：卡片排序法 (Card Sorting)
                Figma 组件化设计系统：Color Token, Typography Scale
                """,
                summary: "课堂整理了用户旅程图的四阶段模型，介绍了卡片排序法确定信息架构，并演示了 Figma 组件化设计系统的搭建方式。",
                todos: ["绘制 Notiee 的用户旅程图初稿", "整理竞品截图到设计文档"]
            )
        ),
        TaggedResult(
            keywords: ["项目", "讨论", "会议", "周会", "站会"],
            result: Result(
                title: "项目进度与分工确认",
                ocrText: """
                Sprint 回顾：已完成 12/15 个 Story Point
                遗留问题：API 超时重试策略待定
                下周目标：完成相机模块集成与 AI 管线对接
                负责人：@小谭 - iOS 端, @小李 - 后端
                """,
                summary: "本次会议回顾了 Sprint 完成情况（80%），讨论了 API 超时的重试策略，并明确了下周的模块分工与集成目标。",
                todos: ["制定 API 超时的指数退避重试方案", "下周三前完成相机模块集成"]
            )
        ),
        TaggedResult(
            keywords: ["英语", "English", "语言"],
            result: Result(
                title: "学术写作结构",
                ocrText: """
                Academic Essay Structure
                1. Introduction – Thesis Statement
                2. Body Paragraphs – Topic Sentence + Evidence + Analysis
                3. Conclusion – Restate & Implications
                Transition words: However, Furthermore, In contrast, Consequently
                """,
                summary: "本节课讲解了学术论文的三段式结构（引言、正文、结论），以及常用过渡词的使用场景。",
                todos: ["用三段式结构改写上周的作文草稿"]
            )
        ),
        TaggedResult(
            keywords: ["物理", "力学", "电磁"],
            result: Result(
                title: "牛顿运动定律应用",
                ocrText: """
                牛顿第二定律: F = ma
                自由体受力图 (Free Body Diagram)
                摩擦力: f = μN
                示例: 斜面上物体的加速度 a = g(sinθ - μcosθ)
                """,
                summary: "本节课通过自由体受力图分析了牛顿第二定律在斜面运动中的应用，推导了含摩擦力情况下的加速度公式。",
                todos: ["完成斜面运动习题 4.3 - 4.7", "画出三种典型场景的受力图"]
            )
        ),
    ]

    private static let fallback = Result(
        title: "课堂笔记摘要",
        ocrText: """
        重点概念梳理
        1. 核心定义与基本原理
        2. 典型例题与解题思路
        3. 课后延伸阅读材料
        板书备注：下周测验范围为第 3-5 章
        """,
        summary: "本次课堂整理了核心定义与基本原理，通过典型例题演示了解题思路，并提示下周测验范围为第 3-5 章。",
        todos: ["复习第 3-5 章核心概念", "整理本次课堂例题到笔记本"]
    )
}
