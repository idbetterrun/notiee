import XCTest
@testable import Notiee

/// 覆盖 `RealAIProcessingService.parseStructuredNote` 的容错解析。
///
/// 背景：视觉/文本模型返回的 JSON 字段形态非确定性——同一字段在不同调用里
/// 可能是数组、字典、字符串，或干脆缺失。任何单个次要字段的形态波动都不能
/// 拖垮整份有效笔记（否则白烧一次 token）。这些用例锁死所有已知畸形格式的
/// 降级行为，防止将来改动引入回归。
final class StructuredNoteParsingTests: XCTestCase {

    private func parse(_ json: String) throws -> AIProcessingResult {
        try RealAIProcessingService.parseStructuredNote(
            responseJSON: json, ocrText: "OCR", modelsUsed: ["m"])
    }

    // MARK: - definitions 的各种形态

    /// 标准形态：对象数组 [{term, explanation}]
    func testDefinitionsObjectArray() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D","todos":[],
         "keyPoints":[],
         "definitions":[{"term":"A","explanation":"a"},{"term":"B","explanation":"b"}]}
        """)
        XCTAssertEqual(r.definitions.map(\.term), ["A", "B"])
        XCTAssertEqual(r.definitions.map(\.explanation), ["a", "b"])
    }

    /// 畸形一：字符串数组 ["术语：解释", ...]（按全角/半角冒号拆分）
    func testDefinitionsStringArray() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D","todos":[],
         "keyPoints":[],
         "definitions":["全国两会：全国人民代表大会和政协的总称","东京审判: 远东国际军事法庭"]}
        """)
        XCTAssertEqual(r.definitions.count, 2)
        XCTAssertEqual(r.definitions[0].term, "全国两会")
        XCTAssertEqual(r.definitions[0].explanation, "全国人民代表大会和政协的总称")
        XCTAssertEqual(r.definitions[1].term, "东京审判")
        XCTAssertEqual(r.definitions[1].explanation, "远东国际军事法庭")
    }

    /// 畸形二：字典 {"术语":"解释", ...}（这次真实踩到的格式）
    func testDefinitionsDictionary() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D","todos":[],
         "keyPoints":[],
         "definitions":{"黄金水道":"通航价值高的内河航道","机械化清漂":"融合多种设备的作业体系"}}
        """)
        XCTAssertEqual(r.definitions.count, 2)
        // 字典无序，用集合断言，不依赖顺序
        let terms = Set(r.definitions.map(\.term))
        XCTAssertEqual(terms, ["黄金水道", "机械化清漂"])
    }

    /// 畸形三：无分隔符的字符串（整串作为 term，explanation 为空）
    func testDefinitionsBarePlainString() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D","todos":[],
         "keyPoints":[],"definitions":["没有冒号的一整串术语"]}
        """)
        XCTAssertEqual(r.definitions.count, 1)
        XCTAssertEqual(r.definitions[0].term, "没有冒号的一整串术语")
        XCTAssertEqual(r.definitions[0].explanation, "")
    }

    /// 畸形四：数组里混入坏元素（数字），坏的跳过，好的保留
    func testDefinitionsArrayWithBadElement() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D","todos":[],
         "keyPoints":[],
         "definitions":[{"term":"A","explanation":"a"}, 42, {"term":"B","explanation":"b"}]}
        """)
        XCTAssertEqual(r.definitions.map(\.term), ["A", "B"])
    }

    /// 畸形五：完全无法识别的形态（definitions 是个数字）→ 空，不抛错
    func testDefinitionsUnrecognizedShapeYieldsEmpty() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D","todos":[],
         "keyPoints":[],"definitions":123}
        """)
        XCTAssertTrue(r.definitions.isEmpty)
    }

    /// definitions 缺失字段 → 空
    func testDefinitionsMissing() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D","todos":[],"keyPoints":[]}
        """)
        XCTAssertTrue(r.definitions.isEmpty)
    }

    /// 对象元素缺 explanation → 补空串
    func testDefinitionObjectMissingExplanation() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D","todos":[],
         "keyPoints":[],"definitions":[{"term":"孤词"}]}
        """)
        XCTAssertEqual(r.definitions.count, 1)
        XCTAssertEqual(r.definitions[0].term, "孤词")
        XCTAssertEqual(r.definitions[0].explanation, "")
    }

    // MARK: - todos / keyPoints 的容错

    /// 正常字符串数组
    func testTodosStringArray() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D",
         "todos":["买菜","开会"],"keyPoints":["要点一"],"definitions":[]}
        """)
        XCTAssertEqual(r.todos, ["买菜", "开会"])
        XCTAssertEqual(r.keyPoints, ["要点一"])
    }

    /// 畸形：todos 是单个字符串而非数组 → 包成单元素数组
    func testTodosSingleString() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D",
         "todos":"只有一条待办","keyPoints":[],"definitions":[]}
        """)
        XCTAssertEqual(r.todos, ["只有一条待办"])
    }

    /// 数组里混入 null / 数字，坏元素跳过，空白项过滤
    func testKeyPointsArrayWithNoiseFiltered() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D","todos":[],
         "keyPoints":["有效", null, 7, "  ", "又一条"],"definitions":[]}
        """)
        XCTAssertEqual(r.keyPoints, ["有效", "又一条"])
    }

    // MARK: - 顶层字段兜底

    /// title 缺失 → "无标题"；detailedContent 缺失 → "无详细内容"；summary 缺失 → ""
    func testTopLevelDefaults() throws {
        let r = try parse("""
        {"todos":[],"keyPoints":[],"definitions":[]}
        """)
        XCTAssertEqual(r.title, "无标题")
        XCTAssertEqual(r.summary, "")
        XCTAssertEqual(r.detailedContent, "无详细内容")
    }

    /// title 为空白串 → 兜底为"无标题"
    func testBlankTitleFallsBack() throws {
        let r = try parse("""
        {"title":"   ","summary":"S","detailedContent":"D",
         "todos":[],"keyPoints":[],"definitions":[]}
        """)
        XCTAssertEqual(r.title, "无标题")
    }

    /// ocrText 透传到结果
    func testOCRTextPassthrough() throws {
        let r = try parse("""
        {"title":"T","summary":"S","detailedContent":"D",
         "todos":[],"keyPoints":[],"definitions":[]}
        """)
        XCTAssertEqual(r.ocrText, "OCR")
    }

    // MARK: - 包裹 / 提取

    /// 被 ```json 代码块包裹 + 前后噪声，仍能提取解析
    func testMarkdownFencedJSONExtracted() throws {
        let r = try parse("""
        这是模型的解释：
        ```json
        {"title":"围栏内","summary":"S","detailedContent":"D",
         "todos":[],"keyPoints":[],"definitions":[]}
        ```
        以上。
        """)
        XCTAssertEqual(r.title, "围栏内")
    }

    /// 顶层完全不是 JSON（截断到无大括号）→ 抛 parsingFailed
    func testNonJSONThrows() {
        XCTAssertThrowsError(try parse("模型返回了一段纯文本，没有任何 JSON"))
    }
}
