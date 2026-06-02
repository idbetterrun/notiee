import Foundation

/// Centralized AI prompt provider. All prompt strings are stored here by language,
/// eliminating the if/else chains scattered through RealAIProcessingService.
struct AIPromptProvider {

    // MARK: - Language Detection

    static func currentLanguage() -> String {
        UserDefaults.standard.string(forKey: UDK.language) ?? "system"
    }

    // MARK: - Prompt Registry
    private static let visionUserPrompt: [String: String] = [
        "en": "Please recognize all text content in the images, including blackboard writing, presentation slides, etc., and maintain the original layout structure as much as possible. Multiple images are coherent, please extract comprehensively. In addition to text content, if there are key charts or formulas, briefly describe them with text. Do not output any nonsense other than the extracted content.",
        "zh-Hant": "請識別圖片中的所有文本內容，包含板書、幻燈片等，並儘可能保持原本的結構輸出。多張圖片是連貫的，請綜合提取。除了文本內容外，如果有關鍵的圖表或公式也可以用文字簡單描述一下。不要輸出任何除了提取內容以外的廢話。",
        "zh-Hans": "请识别图片中的所有文本内容，包含板书、幻灯片等，并尽可能保持原本的结构输出。多张图片是连贯的，请综合提取。除了文本内容外，如果有关键的图表或公式也可以用文字简单描述一下。不要输出任何除了提取内容以外的废话。",
    ]

    private static let visionSystemPrompt: [String: String] = [
        "en": "You are a note organizing assistant. Please analyze the provided images, extract text, summarize the outline, and identify all tasks or action items. Multiple images are taken chronologically, please consider their contents comprehensively.",
        "zh-Hant": "你是一個筆記整理助手。請分析提供的圖片，提取文字，總結大綱，並識別出所有任務或待辦事項。多張圖片是按時間順序拍攝的，請綜合考慮它們的內容。",
        "zh-Hans": "你是一个笔记整理助手。请分析提供的图片，提取文字，总结大纲，并识别出所有任务或待办事项。多张图片是按时间顺序拍摄的，请综合考虑它们的内容。",
    ]

    private static let fullVisionUserPrompt: [String: String] = [
        "en": "Please describe all content in the images comprehensively, including: text content (blackboard writing, slides, captions, labels), visual elements (objects, people, scenes, charts, diagrams), color scheme, layout structure, and overall atmosphere. Do not just extract text — provide a complete visual understanding of each image. Multiple images are coherent, please integrate them holistically. Do not output any nonsense other than the description.",
        "zh-Hant": "請全面描述圖片中的所有內容，包括：文字內容（板書、幻燈片、字幕、標籤等）、視覺元素（物體、人物、場景、圖表、示意圖等）、配色方案、佈局結構以及整體氛圍。不要僅僅提取文字——請提供對每張圖片的完整視覺理解。多張圖片是連貫的，請綜合描述。不要輸出任何除了描述以外的廢話。",
        "zh-Hans": "请全面描述图片中的所有内容，包括：文字内容（板书、幻灯片、字幕、标签等）、视觉元素（物体、人物、场景、图表、示意图等）、配色方案、布局结构以及整体氛围。不要仅仅提取文字——请提供对每张图片的完整视觉理解。多张图片是连贯的，请综合描述。不要输出任何除了描述以外的废话。",
    ]

    private static let fullVisionSystemPrompt: [String: String] = [
        "en": "You are a comprehensive visual analysis assistant. Please examine the provided images in full detail, describing everything you see: all text present, all objects and their spatial relationships, colors, lighting, the overall scene, any charts or diagrams and what they represent, and the mood or atmosphere of the setting. Multiple images are taken chronologically, please consider them as a coherent sequence.",
        "zh-Hant": "你是一個全面的視覺分析助手。請詳細審視提供的圖片，描述你所看到的一切：所有文字內容、所有物體及其空間關係、色彩、光影、整體場景、任何圖表或示意圖及其含義、以及場景的氛圍。多張圖片是按時間順序拍攝的，請將它們視為一個連貫的序列來綜合描述。",
        "zh-Hans": "你是一个全面的视觉分析助手。请详细审视提供的图片，描述你所看到的一切：所有文字内容、所有物体及其空间关系、色彩、光影、整体场景、任何图表或示意图及其含义、以及场景的氛围。多张图片是按时间顺序拍摄的，请将它们视为一个连贯的序列来综合描述。",
    ]

    private static let latexVisionSuffixPrompt: [String: String] = [
        "en": "\\n\\nIMPORTANT: Pay special attention to mathematical formulas, theorems, definitions, and data relationships in charts. Express formulas using LaTeX syntax (wrapped with $$ for display or $ for inline).",
        "zh-Hant": "\\n\\n特別注意：重點關注數學公式、定理、定義以及圖表中的數據關係。對公式使用 LaTeX 語法表達（顯示公式用 $$ 包裹，行內公式用 $ 包裹）。",
        "zh-Hans": "\\n\\n特别注意：重点关注数学公式、定理、定义以及图表中的数据关系。对公式使用 LaTeX 语法表达（显示公式用 $$ 包裹，行内公式用 $ 包裹）。",
    ]

    private static let latexSystemSuffixPrompt: [String: String] = [
        "en": " When presenting formulas, always use LaTeX notation (e.g., $$E=mc^2$$ for display formulas, $x^2+y^2=r^2$ for inline formulas).",
        "zh-Hant": " 呈現公式時，請始終使用 LaTeX 表示法（例如顯示公式用 $$E=mc^2$$，行內公式用 $x^2+y^2=r^2$）。",
        "zh-Hans": " 呈现公式时，请始终使用 LaTeX 表示法（例如显示公式用 $$E=mc^2$$，行内公式用 $x^2+y^2=r^2$）。",
    ]

    // MARK: - Public API

    /// Returns (user prompt, system prompt) for vision OCR extraction
    static func visionPrompt(fullVision: Bool, latex: Bool, language: String = currentLanguage()) -> (user: String, system: String) {
        let lang = normalizedLanguage(language)
        var user = fullVision ? fullVisionUserPrompt[lang]! : visionUserPrompt[lang]!
        var system = fullVision ? fullVisionSystemPrompt[lang]! : visionSystemPrompt[lang]!
        if latex {
            user += latexVisionSuffixPrompt[lang]!
            system += latexSystemSuffixPrompt[lang]!
        }
        return (user, system)
    }

    /// Builds the text structuring prompt with template fields
    static func textPrompt(ocrText: String, enableSummary: Bool, enableDetailedContent: Bool, preset: ScenePreset, language: String = currentLanguage()) -> String {
        let lang = normalizedLanguage(language)
        let hasAdvanced = preset.enableKeyPoints || preset.enableDefinitions
        switch lang {
        case "en": return buildTextPromptEN(ocrText: ocrText, enableSummary: enableSummary, enableDetailedContent: enableDetailedContent, preset: preset, hasAdvanced: hasAdvanced)
        case "zh-Hant": return buildTextPromptZHHant(ocrText: ocrText, enableSummary: enableSummary, enableDetailedContent: enableDetailedContent, preset: preset, hasAdvanced: hasAdvanced)
        default: return buildTextPromptZHHans(ocrText: ocrText, enableSummary: enableSummary, enableDetailedContent: enableDetailedContent, preset: preset, hasAdvanced: hasAdvanced)
        }
    }

    // MARK: - Private Helpers

    private static func normalizedLanguage(_ lang: String) -> String {
        if lang == "system" { return "zh-Hans" }
        if lang.hasPrefix("en") { return "en" }
        if lang.hasPrefix("zh-Hant") || lang.hasPrefix("zh-HK") || lang.hasPrefix("zh-TW") { return "zh-Hant" }
        return "zh-Hans"
    }

    private static func buildTextPromptEN(ocrText: String, enableSummary: Bool, enableDetailedContent: Bool, preset: ScenePreset, hasAdvanced: Bool) -> String {
        var fields = "Fields to extract:\n1. \"title\": Generate a short title based on the content (under 10 words).\n"
        var fieldNum = 2
        if enableSummary {
            fields += "\(fieldNum). \"summary\": Extract a brief summary of the content (under 100 words).\n"
            fieldNum += 1
        }
        if enableDetailedContent {
            fields += "\(fieldNum). \"detailedContent\": Reformat the provided OCR text, fix typos, and organize it into coherent, readable detailed content (if it\'s class notes or meeting minutes, use paragraphs and bullet points for core takeaways). If output is in English, keep it under 2500 characters.\n"
            fieldNum += 1
        }
        if preset.enableTodos {
            fields += "\(fieldNum). \"todos\": If the text contains any tasks or action items to execute, extract them as an array of strings (if none, return an empty array []).\n"
            fieldNum += 1
        }
        if preset.enableKeyPoints {
            fields += "\(fieldNum). \"keyPoints\": Extract 3-5 core knowledge points or key concepts as an array of strings.\n"
            fieldNum += 1
        }
        if preset.enableDefinitions {
            fields += "\(fieldNum). \"definitions\": Extract key terminology and their explanations as [{ \"term\": \"term\", \"explanation\": \"explanation\" }] array (empty array [] if none).\n"
        }
        var extra = ""
        if hasAdvanced { extra += "\nBecause your user is a \(preset.displayName), focus on extracting structured knowledge and actionable insights." }
        return "Please carefully analyze the following text extracted from images.\n\nBased on the requirements below, return a strictly formatted JSON object. Do not return any other content (no Markdown code blocks, no explanations).\n\n\(fields)\(extra)\nHere is the extracted text content:\n\(ocrText)"
    }

    private static func buildTextPromptZHHant(ocrText: String, enableSummary: Bool, enableDetailedContent: Bool, preset: ScenePreset, hasAdvanced: Bool) -> String {
        var fields = "需要提取的字段：\n1. \"title\": 根據內容生成一個簡短的標題（不要超過15個字）。\n"
        var fieldNum = 2
        if enableSummary {
            fields += "\(fieldNum). \"summary\": 提取出簡短的內容摘要（控制在200字以內）。\n"
            fieldNum += 1
        }
        if enableDetailedContent {
            fields += "\(fieldNum). \"detailedContent\": 將提供的 OCR 文本重新排版，修正錯別字，梳理成連貫且易於閱讀的詳細內容（如果是課堂筆記或會議記錄，請分段落、列出核心要點）。注意：最長不要超過 500 字。\n"
            fieldNum += 1
        }
        if preset.enableTodos {
            fields += "\(fieldNum). \"todos\": 如果文本中包含任何需要執行的任務或待辦事項，請提取為一個字符串數組（如果沒有，則返回空數組 []）。\n"
            fieldNum += 1
        }
        if preset.enableKeyPoints {
            fields += "\(fieldNum). \"keyPoints\": 提取文本中的3-5個核心知識點或重點概念，返回字符串數組。\n"
            fieldNum += 1
        }
        if preset.enableDefinitions {
            fields += "\(fieldNum). \"definitions\": 提取文本中的關鍵術語及其解釋，返回 [{ \"term\": \"術語\", \"explanation\": \"解釋\" }] 數組（如果沒有則為空數組 []）。\n"
        }
        var extra = ""
        if hasAdvanced { extra += "\n因為你的使用者是\(preset.displayName)，請專注於提取結構化知識和可執行的洞見。" }
        return "請仔細分析以下提取自圖片的文字內容。\n\n根據以下要求，返回一個嚴格格式化的 JSON 對象。不要返回任何其他內容（不要帶 Markdown 代碼塊，不要有解釋說明）。\n\n\(fields)\(extra)\n以下是提取的文字內容：\n\(ocrText)"
    }

    private static func buildTextPromptZHHans(ocrText: String, enableSummary: Bool, enableDetailedContent: Bool, preset: ScenePreset, hasAdvanced: Bool) -> String {
        var fields = "需要提取的字段：\n1. \"title\": 根据内容生成一个简短的标题（不要超过15个字）。\n"
        var fieldNum = 2
        if enableSummary {
            fields += "\(fieldNum). \"summary\": 提取出简短的内容摘要（控制在200字以内）。\n"
            fieldNum += 1
        }
        if enableDetailedContent {
            fields += "\(fieldNum). \"detailedContent\": 将提供的 OCR 文本重新排版，修正错别字，梳理成连贯且易于阅读的详细内容（如果是课堂笔记或会议记录，请分段落、列出核心要点）。注意：最长不要超过 500 字。\n"
            fieldNum += 1
        }
        if preset.enableTodos {
            fields += "\(fieldNum). \"todos\": 如果文本中包含任何需要执行的任务或待办事项，请提取为一个字符串数组（如果没有，则返回空数组 []）。\n"
            fieldNum += 1
        }
        if preset.enableKeyPoints {
            fields += "\(fieldNum). \"keyPoints\": 提取文本中的3-5个核心知识点或重点概念，返回字符串数组。\n"
            fieldNum += 1
        }
        if preset.enableDefinitions {
            fields += "\(fieldNum). \"definitions\": 提取文本中的关键术语及其解释，返回 [{ \"term\": \"术语\", \"explanation\": \"解释\" }] 数组（如果没有则为空数组 []）。\n"
        }
        var extra = ""
        if hasAdvanced { extra += "\n因为你的使用者是\(preset.displayName)，请专注于提取结构化知识和可执行的洞见。" }
        return "请仔细分析以下提取自图片的文字内容。\n\n根据以下要求，返回一个严格格式化的 JSON 对象。不要返回任何其他内容（不要带 Markdown 代码块，不要有解释说明）。\n\n\(fields)\(extra)\n以下是提取的文字内容：\n\(ocrText)"
    }
}
