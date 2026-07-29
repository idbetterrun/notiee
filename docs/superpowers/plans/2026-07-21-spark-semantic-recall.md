# Spark 普通问答语义召回 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Spark 普通问答（非 Agent）从「每轮倾倒最近 150 条」改为「近期锚点 + 语义召回」的分层混合，破除 150 条硬天花板并大幅降低每轮 token。

**Architecture:** 新增 `SparkRecordRecall`（@MainActor，持有已有的 `SemanticSearchEngine`）在调用 LLM 前挑选记录：锚点层（最近 N 条，标题+摘要）+ 语义层（对本轮 query 召回的 top-K，注入全文），去重合并成一个有序数组 `RecalledRecords`。挑选在 `SparkViewModel`（主线程）完成，把结果传给 off-main 的 `ask()`；`buildSystemPrompt` 按锚点/语义两段渲染但连续编号。`[来源N]` 改为按 `RecalledRecords.records` 的显式位置映射，不再依赖「记录是全量列表前缀」的隐含耦合。

**Tech Stack:** Swift / SwiftUI / XCTest；已有 `Services/Semantic/`（NLEmbedding 本地向量 + 云端可选 + `EmbeddingIndex` 旁路存储 + `SemanticRanker`）。

**Spec（背景与决策依据）:** `docs/Spark语义召回改造方案.md`

## Global Constraints

- **两个 Target（`Notiee` 免费 / `Notiee+` BYOK）都要编译通过。** 本改动全在共享代码，无需 `#if NOTIEE_PLUS` 分叉——embedding 来源差异已被 `HybridEmbeddingService.preferCloud` 吸收。
- **Xcode 工程用 `PBXFileSystemSynchronizedRootGroup`**：新 `.swift` 放进 `Notiee/`（源码）或 `NotieeTests/`（测试）对应目录即自动加入 target，**不改 `.pbxproj`**。
- **单测命令**（全程统一）：
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodebuild -project Notiee.xcodeproj -scheme Notiee \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    test -only-testing:NotieeTests/<测试类名> 2>&1 | tail -20
  ```
  期望末尾 `** TEST SUCCEEDED **`；失败为 `** TEST FAILED **`。首次跑会解析 SPM，较慢。
- **构建命令**（改共享文件后两个 scheme 都要过）：
  ```bash
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  xcodebuild build -project Notiee.xcodeproj -scheme <Notiee|Notiee+> -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
  ```
- **测试风格**：`import XCTest` + `@testable import Notiee`；涉及 `@MainActor` 类型的测试类加 `@MainActor`（参考 `NotieeTests/SemanticSearchEngineTests.swift`）。
- **提交**：频繁提交，每个 Task 一提交。当前在 `main`，**先开分支** `feature/spark-semantic-recall`。
- **隐私不回归**：语义层**绝不**注入 `isEncrypted` 记录的正文（`SemanticSearchEngine` 已跳过加密记录）。锚点层维持现状（仅 `!isDeleted` 过滤，只含标题+摘要），不改动今天的行为。

---

## 文件结构总览

**新增：**
- `Notiee/Features/Spark/SparkRecordRecall.swift` — `RecalledRecords` 值类型 + `SparkRecordRecall`（分层挑选：纯 `merge` + 异步 `recall`）
- `NotieeTests/SparkRecordRecallTests.swift` — `merge` 纯逻辑 + `recall` 异步（stub 引擎）测试

**修改：**
- `Notiee/Services/Semantic/SemanticSearchEngine.swift` — 加 `static func liveForSpark(settingsStore:)` 装配工厂（DRY）
- `Notiee/Features/Spark/SparkAIService.swift` — `ask`/`buildSystemPrompt` 改用 `RecalledRecords`；删除 `maxRecordsInPrompt` 倾倒逻辑
- `Notiee/Features/Spark/BackendSparkAIService.swift` — `ask` 改用 `RecalledRecords`
- `Notiee/Features/Spark/SparkViewModel.swift` — 注入引擎/recall；`processQuestion` 先召回、传入 `ask`、引用按 `recall.records` 映射；`makeAgentExecutor` 改用工厂；冷启动 `warmUpSemanticIndex()`
- `Notiee/Features/Spark/SparkView.swift` — `onAppear` 触发一次冷启动回填
- `NotieeTests/SparkViewModelTests.swift` — 更新 `MockAIService.ask` 签名；新增引用映射测试
- `NotieeTests/SparkPromptRecallTests.swift`（新）— `buildSystemPrompt(recall:)` 两段渲染测试

---

## 关键接口契约（所有 Task 共享，先读）

```swift
// SparkRecordRecall.swift
/// 一轮问答要注入 prompt 的记录，锚点在前、语义在后，[记录1..N] 按此数组顺序编号。
struct RecalledRecords: Sendable {
    let records: [NoteRecord]      // 合并去重后的有序列表
    let semanticStartIndex: Int    // records[semanticStartIndex...] 是全文语义层；之前是锚点层
}

@MainActor
struct SparkRecordRecall {
    let engine: SemanticSearching  // 复用 NoteSearchTool.swift 里定义的 @MainActor 协议
    var anchorCount: Int = 15
    var semanticLimit: Int = 8
    var mergedCap: Int = 20

    /// 纯函数：锚点原序在前，语义去掉已在锚点里的，整体截到 cap。
    static func merge(anchors: [NoteRecord], semantic: [NoteRecord], cap: Int) -> RecalledRecords

    /// 异步：取锚点（最近 anchorCount，仅 !isDeleted）+ 语义召回（候选排除 isDeleted/isEncrypted），合并。
    func recall(query: String, from allRecords: [NoteRecord]) async -> RecalledRecords
}

// SparkAIServing 协议（SparkAIService.swift）——签名变更
func ask(question: String, recall: RecalledRecords,
         recentRounds: [ConversationRound], upcomingEvents: [ScheduledEvent])
    async throws -> (text: String, tokens: Int)

// buildSystemPrompt（SparkAIService.swift，internal）——签名变更
func buildSystemPrompt(recall: RecalledRecords,
                       recentRounds: [ConversationRound],
                       upcomingEvents: [ScheduledEvent]) -> String

// SemanticSearchEngine.swift——新增工厂
static func liveForSpark(settingsStore: AppSettingsPersisting) -> SemanticSearchEngine
```

> **`SemanticSearching` 协议现状**（`NoteSearchTool.swift` 第 4-9 行）只有 `func search(query:in:limit:) async -> [NoteRecord]`，且 `extension SemanticSearchEngine: SemanticSearching {}`。Task 6 会给它加一个 `backfill` 方法用于冷启动回填与测试。

---

### Task 1: `RecalledRecords` + 纯 `merge` 逻辑

**Files:**
- Create: `Notiee/Features/Spark/SparkRecordRecall.swift`
- Test: `NotieeTests/SparkRecordRecallTests.swift`

**Interfaces:**
- Produces: `RecalledRecords`（`records: [NoteRecord]`, `semanticStartIndex: Int`）；`SparkRecordRecall.merge(anchors:semantic:cap:) -> RecalledRecords`

- [ ] **Step 1: 写失败测试**

`NotieeTests/SparkRecordRecallTests.swift`：
```swift
import XCTest
@testable import Notiee

@MainActor
final class SparkRecordRecallTests: XCTestCase {
    private func rec(_ title: String) -> NoteRecord {
        NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
    }

    func testMerge_semanticExcludesAnchorDuplicates_andReportsBoundary() {
        let a1 = rec("锚点1"); let a2 = rec("锚点2")
        let s1 = rec("语义1")
        // s 里混入一个和锚点重复的 a1
        let out = SparkRecordRecall.merge(anchors: [a1, a2], semantic: [a1, s1], cap: 20)
        XCTAssertEqual(out.records.map { $0.id }, [a1.id, a2.id, s1.id], "锚点在前、去掉语义里的重复")
        XCTAssertEqual(out.semanticStartIndex, 2, "语义层从第 3 条(下标2)开始")
    }

    func testMerge_capTruncates_andClampsBoundary() {
        let anchors = (0..<3).map { rec("锚\($0)") }
        let semantic = (0..<10).map { rec("语\($0)") }
        let out = SparkRecordRecall.merge(anchors: anchors, semantic: semantic, cap: 5)
        XCTAssertEqual(out.records.count, 5, "截到 cap")
        XCTAssertEqual(out.semanticStartIndex, 3, "边界=锚点数")
        XCTAssertEqual(out.records.prefix(3).map { $0.id }, anchors.map { $0.id })
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkRecordRecallTests 2>&1 | tail -20`
Expected: FAIL（`SparkRecordRecall` / `RecalledRecords` 未定义，编译错误）

- [ ] **Step 3: 写最小实现**

`Notiee/Features/Spark/SparkRecordRecall.swift`：
```swift
import Foundation

/// 一轮普通问答要注入 prompt 的记录集合，锚点在前、语义在后。
/// `[记录1..N]` 与 `[来源N]` 均按 `records` 数组的位置编号（1-based）。
struct RecalledRecords: Sendable {
    let records: [NoteRecord]
    /// records[semanticStartIndex...] 是全文语义层；前面是标题+摘要的锚点层。
    let semanticStartIndex: Int

    static let empty = RecalledRecords(records: [], semanticStartIndex: 0)
}

@MainActor
struct SparkRecordRecall {
    let engine: SemanticSearching
    var anchorCount: Int = 15
    var semanticLimit: Int = 8
    var mergedCap: Int = 20

    init(engine: SemanticSearching, anchorCount: Int = 15, semanticLimit: Int = 8, mergedCap: Int = 20) {
        self.engine = engine
        self.anchorCount = anchorCount
        self.semanticLimit = semanticLimit
        self.mergedCap = mergedCap
    }

    /// 锚点原序在前；语义去掉已在锚点里的；整体截到 cap。
    static func merge(anchors: [NoteRecord], semantic: [NoteRecord], cap: Int) -> RecalledRecords {
        let anchorIDs = Set(anchors.map { $0.id })
        let extras = semantic.filter { !anchorIDs.contains($0.id) }
        let merged = Array((anchors + extras).prefix(cap))
        let boundary = min(anchors.count, merged.count)
        return RecalledRecords(records: merged, semanticStartIndex: boundary)
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkRecordRecallTests 2>&1 | tail -20`
Expected: PASS（`Test Suite 'SparkRecordRecallTests' passed`）

- [ ] **Step 5: 提交**

```bash
git checkout -b feature/spark-semantic-recall
git add Notiee/Features/Spark/SparkRecordRecall.swift NotieeTests/SparkRecordRecallTests.swift
git commit -m "feat(spark): add RecalledRecords + pure layered merge"
```

---

### Task 2: 异步 `recall` + 引擎装配工厂

**Files:**
- Modify: `Notiee/Features/Spark/SparkRecordRecall.swift`（加 `recall`）
- Modify: `Notiee/Services/Semantic/SemanticSearchEngine.swift`（加 `liveForSpark` 工厂）
- Modify: `Notiee/Features/Spark/SparkViewModel.swift:527-540`（`makeAgentExecutor` 改用工厂，DRY）
- Test: `NotieeTests/SparkRecordRecallTests.swift`（加 `recall` 异步测试）

**Interfaces:**
- Consumes: `SparkRecordRecall.merge`（Task 1）；`SemanticSearching.search`（已有）
- Produces: `SparkRecordRecall.recall(query:from:) async -> RecalledRecords`；`SemanticSearchEngine.liveForSpark(settingsStore:) -> SemanticSearchEngine`

- [ ] **Step 1: 写失败测试（recall 异步）**

在 `SparkRecordRecallTests` 里追加（含一个 stub 引擎）：
```swift
private final class StubSearch: SemanticSearching {
    let result: [NoteRecord]
    private(set) var lastCandidates: [NoteRecord] = []
    init(result: [NoteRecord]) { self.result = result }
    func search(query: String, in records: [NoteRecord], limit: Int) async -> [NoteRecord] {
        lastCandidates = records
        return result
    }
}

func testRecall_mergesAnchorsAndSemantic_excludesEncryptedFromCandidates() async {
    let now = Date()
    func recAt(_ title: String, _ ago: TimeInterval, encrypted: Bool = false) -> NoteRecord {
        var r = NoteRecord(id: UUID(), capturedAt: now.addingTimeInterval(-ago), localImagePaths: ["x"], title: title)
        r.isEncrypted = encrypted
        return r
    }
    let newest = recAt("最新", 10)
    let secret = recAt("加密", 20, encrypted: true)
    let old = recAt("很老的记录", 99999)     // 语义命中的老记录
    let all = [newest, secret, old]

    let stub = StubSearch(result: [old])       // 语义引擎召回老记录
    let recaller = SparkRecordRecall(engine: stub, anchorCount: 1, semanticLimit: 5, mergedCap: 20)
    let out = await recaller.recall(query: "老", from: all)

    // 锚点=最近1条(newest)；语义补 old；secret 不在语义候选里
    XCTAssertEqual(out.records.map { $0.id }, [newest.id, old.id])
    XCTAssertEqual(out.semanticStartIndex, 1)
    XCTAssertFalse(stub.lastCandidates.contains { $0.id == secret.id }, "加密记录不进语义候选")
}
```

> `NoteRecord.isEncrypted` 是可变属性（`var`）；若初始化器不含该参数，按上例先构造再赋值。

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkRecordRecallTests 2>&1 | tail -20`
Expected: FAIL（`recall` 未定义）

- [ ] **Step 3: 实现 `recall`**

在 `SparkRecordRecall` 里加：
```swift
    func recall(query: String, from allRecords: [NoteRecord]) async -> RecalledRecords {
        let live = allRecords.filter { !$0.isDeleted }
        let anchors = Array(
            live.sorted { $0.capturedAt > $1.capturedAt }.prefix(anchorCount)
        )
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return RecalledRecords(records: anchors, semanticStartIndex: anchors.count)
        }
        let candidates = live.filter { !$0.isEncrypted }
        let semantic = await engine.search(query: trimmed, in: candidates, limit: semanticLimit)
        return Self.merge(anchors: anchors, semantic: semantic, cap: mergedCap)
    }
```

- [ ] **Step 4: 加装配工厂并让 `makeAgentExecutor` 复用（DRY）**

`Notiee/Services/Semantic/SemanticSearchEngine.swift` 末尾（`class` 内）加：
```swift
    /// Spark 用的标准装配：本地 NLEmbedding + 可选云端（复用文本模型 key）+ 共享索引。
    static func liveForSpark(settingsStore: AppSettingsPersisting) -> SemanticSearchEngine {
        let embeddingModel = UserDefaults.standard.string(forKey: "spark.semanticSearch.embeddingModel") ?? "text-embedding-3-small"
        let cloud = CloudEmbeddingService(configProvider: {
            let cfg = settingsStore.loadConfiguration(for: .text)
            return CloudEmbeddingService.Config(endpoint: cfg.activeEndpoint, apiKey: cfg.apiKey, model: embeddingModel)
        })
        let hybrid = HybridEmbeddingService(
            local: LocalEmbeddingService(),
            cloud: cloud,
            preferCloud: { UserDefaults.standard.bool(forKey: "spark.semanticSearch.useCloud") }
        )
        return SemanticSearchEngine(embeddingService: hybrid, index: .live)
    }
```
然后把 `SparkViewModel.makeAgentExecutor()`（约 530-540 行）里手工装配的 `embeddingModel`/`cloud`/`hybrid`/`searchEngine` 五行替换为：
```swift
        let searchEngine = SemanticSearchEngine.liveForSpark(settingsStore: settingsStore)
```
（`NoteSearchTool(recordManager:searchEngine:searchEngine)` 保持不变。）

- [ ] **Step 5: 运行测试 + 两 scheme 构建**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkRecordRecallTests 2>&1 | tail -20` → PASS
Run: `xcodebuild build -scheme Notiee ...` 与 `-scheme Notiee+ ...` → 均 `** BUILD SUCCEEDED **`

- [ ] **Step 6: 提交**

```bash
git add Notiee/Features/Spark/SparkRecordRecall.swift Notiee/Services/Semantic/SemanticSearchEngine.swift Notiee/Features/Spark/SparkViewModel.swift NotieeTests/SparkRecordRecallTests.swift
git commit -m "feat(spark): async recall + shared semantic-engine factory"
```

---

### Task 3: `buildSystemPrompt(recall:)` 两段渲染

**Files:**
- Modify: `Notiee/Features/Spark/SparkAIService.swift:475-602`（`buildSystemPrompt` 签名 + 记录块）
- Test: `NotieeTests/SparkPromptRecallTests.swift`

**Interfaces:**
- Consumes: `RecalledRecords`（Task 1）
- Produces: `buildSystemPrompt(recall:recentRounds:upcomingEvents:) -> String`

- [ ] **Step 1: 写失败测试**

`NotieeTests/SparkPromptRecallTests.swift`：
```swift
import XCTest
@testable import Notiee

@MainActor
final class SparkPromptRecallTests: XCTestCase {
    private func makeService() -> SparkAIService {
        // 用默认 store 即可；本测试只看拍记块渲染，不触网。
        SparkAIService()
    }
    private func rec(_ title: String, summary: String, body: String) -> NoteRecord {
        var r = NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
        r.summary = summary
        r.detailedContent = body
        return r
    }

    func testPrompt_rendersAnchorAndSemanticLayers_withContinuousNumbering() {
        let anchor = rec("锚点笔记", summary: "锚点摘要", body: "锚点正文不该整段进 prompt")
        let semantic = rec("语义老笔记", summary: "语义摘要", body: "语义层应注入的全文内容ABC")
        let recall = RecalledRecords(records: [anchor, semantic], semanticStartIndex: 1)

        let p = makeService().buildSystemPrompt(recall: recall, recentRounds: [], upcomingEvents: [])

        XCTAssertTrue(p.contains("[记录1]"), "锚点编号")
        XCTAssertTrue(p.contains("[记录2]"), "语义编号连续")
        XCTAssertTrue(p.contains("语义摘要") || p.contains("语义层应注入的全文内容ABC"), "语义记录可见")
        XCTAssertTrue(p.contains("语义层应注入的全文内容ABC"), "语义层注入全文正文")
        XCTAssertTrue(p.contains("共 2 条"), "记录总数=合并后条数")
    }

    func testPrompt_emptyRecall_noRecordBlockCrash() {
        let p = makeService().buildSystemPrompt(recall: .empty, recentRounds: [], upcomingEvents: [])
        XCTAssertTrue(p.contains("共 0 条"))
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkPromptRecallTests 2>&1 | tail -20`
Expected: FAIL（`buildSystemPrompt(recall:...)` 不存在——当前签名是 `records:`）

- [ ] **Step 3: 改 `buildSystemPrompt`**

把 `func buildSystemPrompt(records:recentRounds:upcomingEvents:)` 的签名改为 `recall: RecalledRecords`，并替换开头的 `recordBlock` 组装（原第 486-494 行）为分层渲染：
```swift
        let all = recall.records
        let anchors = Array(all.prefix(recall.semanticStartIndex))
        let semantic = Array(all.dropFirst(recall.semanticStartIndex))

        var recordBlock = ""
        // 锚点层：标题 + 摘要（100 字），保浏览/时序
        for (i, r) in anchors.enumerated() {
            let d = r.capturedAt.formatted(date: .abbreviated, time: .shortened)
            let s = r.summary.isEmpty ? "" : "摘要：\(trunc(r.summary, 100))"
            recordBlock += "[记录\(i+1)] \(r.title) | \(d)\n\(s)\n"
        }
        // 语义层：与本轮提问相关的历史记录，注入全文（800 字），编号紧接锚点层
        if !semantic.isEmpty {
            recordBlock += "\n【与当前问题语义相关的历史记录（可能超出最近范围）】\n"
            for (j, r) in semantic.enumerated() {
                let n = recall.semanticStartIndex + j + 1
                let d = r.capturedAt.formatted(date: .abbreviated, time: .shortened)
                let body = SparkAIService.recordFullText(r)
                recordBlock += "[记录\(n)] \(r.title) | \(d)\n\(trunc(body, 800))\n"
            }
        }
        if !all.isEmpty {
            recordBlock = "以下拍记：[记录1]起为最近的拍记（按时间倒序），之后为语义相关的历史记录。\n" + recordBlock
        }
```
并把模板里 `## 当前拍记（共 \(records.count) 条）` 改成 `## 当前拍记（共 \(all.count) 条）`。

在 `SparkAIService` 里加一个组织全文的静态辅助（复用 `RecordEmbeddingText` 的取材口径，但独立可调）：
```swift
    /// 语义层注入用的记录全文：标题/摘要/正文/OCR 拼接（与向量取材同源，便于命中一致）。
    static func recordFullText(_ r: NoteRecord) -> String {
        [r.title, r.summary, r.detailedContent, r.ocrText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
```

- [ ] **Step 4: 运行确认通过**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkPromptRecallTests 2>&1 | tail -20`
Expected: PASS

> 本步会让 `SparkAIService.ask` 与 `BackendSparkAIService.ask` 暂时编译不过（还在用旧的 `buildSystemPrompt(records:)`）——Task 4 一起修复；本 Task 只跑目标测试类，不跑全量构建。

- [ ] **Step 5: 提交**

```bash
git add Notiee/Features/Spark/SparkAIService.swift NotieeTests/SparkPromptRecallTests.swift
git commit -m "feat(spark): layered record block (anchor+summary / semantic+fulltext)"
```

---

### Task 4: `ask(recall:)` 协议变更 + 两个服务实现

**Files:**
- Modify: `Notiee/Features/Spark/SparkAIService.swift`（协议 `SparkAIServing.ask` + 实现 `ask`；删 `maxRecordsInPrompt` 用法）
- Modify: `Notiee/Features/Spark/BackendSparkAIService.swift:29-43`（`ask`）
- Modify: `NotieeTests/SparkViewModelTests.swift:11`（`MockAIService.ask` 签名）

**Interfaces:**
- Consumes: `RecalledRecords`（Task 1）、`buildSystemPrompt(recall:)`（Task 3）
- Produces: `ask(question:recall:recentRounds:upcomingEvents:) async throws -> (text:String, tokens:Int)`（协议 + 两实现 + Mock）

- [ ] **Step 1: 改协议签名**

`SparkAIService.swift` 协议 `SparkAIServing`（第 48 行）：
```swift
    func ask(question: String, recall: RecalledRecords,
             recentRounds: [ConversationRound], upcomingEvents: [ScheduledEvent])
        async throws -> (text: String, tokens: Int)
```

- [ ] **Step 2: 改 `SparkAIService.ask`（第 185-…）**

删掉 `activeRecords = allRecords...prefix(Self.maxRecordsInPrompt)`，改为直接用传入的 `recall`：
```swift
    func ask(question: String, recall: RecalledRecords,
             recentRounds: [ConversationRound], upcomingEvents: [ScheduledEvent])
        async throws -> (text: String, tokens: Int) {
        let textConfig = settingsStore.loadConfiguration(for: .text)
        guard textConfig.isComplete else { throw SparkAIError.missingConfiguration }

        let systemPrompt = buildSystemPrompt(recall: recall, recentRounds: recentRounds, upcomingEvents: upcomingEvents)
        let userPrompt = "用户说：\(question)"
        // ……以下调用 LLM 的原逻辑保持不变（systemPrompt/userPrompt 已就绪）……
    }
```
删除 `static let maxRecordsInPrompt = 150`（第 55 行）——全库最后一个使用点在下一步一并去除。

- [ ] **Step 3: 改 `BackendSparkAIService.ask`（第 29-43 行）**

```swift
    func ask(question: String, recall: RecalledRecords,
             recentRounds: [ConversationRound], upcomingEvents: [ScheduledEvent])
        async throws -> (text: String, tokens: Int) {
        let systemPrompt = local.buildSystemPrompt(
            recall: recall, recentRounds: recentRounds, upcomingEvents: upcomingEvents)
        let userPrompt = "用户说：\(question)"
        let result = try await chat(
            messages: [["role": "user", "content": userPrompt]],
            system: systemPrompt)
        accumulatePublic(result.tokens)
        return result
    }
```
（删掉原先的 `activeRecords`/`SparkAIService.maxRecordsInPrompt` 两行。）

- [ ] **Step 4: 改测试里的 Mock 签名**

`NotieeTests/SparkViewModelTests.swift:11` 的 `MockAIService.ask` 改为：
```swift
    func ask(question: String, recall: RecalledRecords,
             recentRounds: [ConversationRound], upcomingEvents: [ScheduledEvent])
        async throws -> (text: String, tokens: Int) {
        // 保留原 Mock 返回值逻辑（若无则返回固定串）
    }
```

- [ ] **Step 5: 两 scheme 构建 + 现有 Spark 测试**

Run: `xcodebuild build -scheme Notiee ...` 与 `-scheme Notiee+ ...` → 均 `** BUILD SUCCEEDED **`
Run: `xcodebuild ... test -only-testing:NotieeTests/SparkViewModelTests 2>&1 | tail -20` → PASS

- [ ] **Step 6: 提交**

```bash
git add Notiee/Features/Spark/SparkAIService.swift Notiee/Features/Spark/BackendSparkAIService.swift NotieeTests/SparkViewModelTests.swift
git commit -m "refactor(spark): ask() consumes RecalledRecords; drop 150-record dump"
```

---

### Task 5: `SparkViewModel` 召回接线 + `[来源N]` 按 record.id 映射

**Files:**
- Modify: `Notiee/Features/Spark/SparkViewModel.swift`（init 注入引擎；`processQuestion` 召回 + 传参 + 引用映射）
- Test: `NotieeTests/SparkViewModelTests.swift`（引用映射测试）

**Interfaces:**
- Consumes: `SparkRecordRecall`（Task 1-2）、`ask(recall:)`（Task 4）
- Produces: `SparkViewModel` 在普通问答时用 `recall.records` 做引用映射

- [ ] **Step 1: 写失败测试（引用映射正确性——本改造最高风险点）**

在 `SparkViewModelTests` 加：让 Mock 引擎召回一个「跳进来的老记录」，Mock AI 回复带 `[来源2]`，断言 citation 指向该老记录，而不是全量列表第 2 条。
```swift
func testCitation_mapsToRecalledRecord_notFullListPosition() async throws {
    // 3 条记录，语义引擎只把「老记录」召回为语义层第 1 条
    let newest = NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: "最新")
    let mid    = NoteRecord(id: UUID(), capturedAt: Date().addingTimeInterval(-100), localImagePaths: ["x"], title: "中间")
    let oldHit = NoteRecord(id: UUID(), capturedAt: Date().addingTimeInterval(-9999), localImagePaths: ["x"], title: "老命中")

    let stub = StubSearch(result: [oldHit])   // 复用 Task 2 的 StubSearch（若在别的文件，挪成 internal 或就地再定义）
    // anchorCount=1 → 锚点=[newest]，语义补 oldHit → recall.records=[newest, oldHit]
    let vm = SparkViewModel(
        aiService: MockAIService(reply: "见[来源2]"),   // 引用第 2 条 = oldHit
        // …其余 mock store 依 SparkViewModelTests 既有构造…
        searchEngine: stub, anchorCount: 1
    )
    vm.recordsProvider = { [newest, mid, oldHit] }
    await vm.sendAndWait("老的那条")   // 用测试里已有的发送+等待助手；若无则直接 await 私有管线的可测入口

    let cites = vm.messages.last(where: { $0.role == .assistant })?.citations ?? []
    XCTAssertEqual(cites.map { $0.recordID }, [oldHit.id], "[来源2] 必须映射到 recall.records[1]=oldHit")
}
```
> 若 `SparkViewModel` 现有测试没有「发送并等待完成」的同步助手，本 Task 需先加一个 `@MainActor func sendForTest(_:) async` 之类的测试可见入口，或将 `processQuestion` 的 citation 计算抽成可单测的纯函数 `mapCitations(text:records:) -> [Citation]` 并直接测它（更稳，推荐）。

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkViewModelTests 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: 注入引擎 + 改 `processQuestion`**

`SparkViewModel.init` 增参（默认 nil → 用 live 工厂）：
```swift
    private let recordRecall: SparkRecordRecall
    // init 增：searchEngine: SemanticSearching? = nil, anchorCount: Int = 15
    // body:
    let engine = searchEngine ?? SemanticSearchEngine.liveForSpark(settingsStore: settingsStore)
    self.recordRecall = SparkRecordRecall(engine: engine, anchorCount: anchorCount)
    self.semanticEngine = engine   // 供 Task 6 冷启动回填
```
`processQuestion(_:_:)`（第 181-）改：在 detached `ask` 之前、MainActor 上先召回：
```swift
        let allRecs = recordsProvider?() ?? []
        let recall = await recordRecall.recall(query: q, from: allRecs)   // MainActor
        let recentRounds = buildRecentRounds()
        let upcoming = calendarManager?.allEvents ?? []

        let (full, tokens) = try await withCheckedThrowingContinuation { cont in
            let service = aiService
            Task.detached {
                do { cont.resume(returning: try await service.ask(
                        question: q, recall: recall, recentRounds: recentRounds, upcomingEvents: upcoming)) }
                catch { cont.resume(throwing: error) }
            }
        }
```
引用映射（第 216-229 行）从「全量 `all`」改为「`recall.records`」：
```swift
        let promptRecords = recall.records
        let (clean, ops, cits) = await Task.detached {
            let visible = SparkAIService.stripThinkTags(full)
            let (clean, ops) = service.extractMemory(from: visible)
            var cIdx = service.extractCitations(from: clean, recordCount: promptRecords.count)
            if cIdx.isEmpty { cIdx = service.extractCitationsFallback(from: clean, records: promptRecords) }
            let cits: [Citation] = cIdx.compactMap { idx in
                guard idx < promptRecords.count else { return nil }
                let r = promptRecords[idx]
                return Citation(recordID: r.id, title: r.title, capturedAt: r.capturedAt)
            }
            let cleanStripped = SparkAIService.stripCitationMarkers(clean)
            return (cleanStripped, ops, cits)
        }.value
```

- [ ] **Step 4: 运行确认通过 + 两 scheme 构建**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkViewModelTests 2>&1 | tail -20` → PASS
Run: 两 scheme `xcodebuild build ...` → 均 SUCCEEDED

- [ ] **Step 5: 提交**

```bash
git add Notiee/Features/Spark/SparkViewModel.swift NotieeTests/SparkViewModelTests.swift
git commit -m "fix(spark): map [来源N] by recalled record.id, not full-list position"
```

---

### Task 6: 冷启动语义索引回填

**Files:**
- Modify: `Notiee/Features/Spark/Agent/Tools/NoteSearchTool.swift:4-9`（`SemanticSearching` 加 `backfill`）
- Modify: `Notiee/Services/Semantic/SemanticSearchEngine.swift`（已有 `backfill`，仅确认 protocol conformance）
- Modify: `Notiee/Features/Spark/SparkViewModel.swift`（`warmUpSemanticIndex()`）
- Modify: `Notiee/Features/Spark/SparkView.swift:100-105`（`onAppear` 调一次）
- Test: `NotieeTests/SparkRecordRecallTests.swift`（stub 计数）

**Interfaces:**
- Consumes: `SemanticSearchEngine.backfill(records:)`（已存在，第 51 行附近）
- Produces: `SemanticSearching.backfill(records:)`；`SparkViewModel.warmUpSemanticIndex()`

- [ ] **Step 1: 写失败测试**

给 `StubSearch` 加 `backfill` 计数，测 `warmUpSemanticIndex` 只回填一次：
```swift
func testWarmUp_backfillsOnce() async {
    let stub = StubSearch(result: [])   // 给 StubSearch 补 backfill 计数属性
    let vm = SparkViewModel(aiService: MockAIService(reply: ""), /* …stores… */ searchEngine: stub)
    vm.recordsProvider = { [NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: "a")] }
    await vm.warmUpSemanticIndex()
    await vm.warmUpSemanticIndex()
    XCTAssertEqual(stub.backfillCount, 1, "只回填一次")
}
```

- [ ] **Step 2: 运行确认失败**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkRecordRecallTests 2>&1 | tail -20`
Expected: FAIL（`backfill` 不在协议 / `warmUpSemanticIndex` 未定义）

- [ ] **Step 3: 实现**

`NoteSearchTool.swift` 协议加方法：
```swift
@MainActor
protocol SemanticSearching {
    func search(query: String, in records: [NoteRecord], limit: Int) async -> [NoteRecord]
    func backfill(records: [NoteRecord]) async
}
```
`SemanticSearchEngine` 已有 `backfill(records:)`，`extension SemanticSearchEngine: SemanticSearching {}` 自动满足。
`SparkViewModel` 加：
```swift
    private var didWarmUpSemantic = false
    func warmUpSemanticIndex() async {
        guard !didWarmUpSemantic else { return }
        didWarmUpSemantic = true
        let recs = (recordsProvider?() ?? []).filter { !$0.isDeleted }
        await semanticEngine.backfill(records: recs)
    }
```
`StubSearch` 加 `private(set) var backfillCount = 0; func backfill(records:) async { backfillCount += 1 }`。

- [ ] **Step 4: `SparkView.onAppear` 触发**

`SparkView.swift` 第 100-105 行 `onAppear` 里加：
```swift
            Task { await viewModel.warmUpSemanticIndex() }
```

- [ ] **Step 5: 运行测试 + 两 scheme 构建**

Run: `xcodebuild ... test -only-testing:NotieeTests/SparkRecordRecallTests 2>&1 | tail -20` → PASS
Run: 两 scheme build → SUCCEEDED

- [ ] **Step 6: 提交**

```bash
git add Notiee/Features/Spark/Agent/Tools/NoteSearchTool.swift Notiee/Features/Spark/SparkViewModel.swift Notiee/Features/Spark/SparkView.swift NotieeTests/SparkRecordRecallTests.swift
git commit -m "feat(spark): warm up semantic index on Spark first appear"
```

---

### Task 7: 手动验收 + 全量测试

**Files:** 无代码改动（验收关卡）

- [ ] **Step 1: 全量 Spark 相关测试**

Run:
```bash
xcodebuild ... test \
  -only-testing:NotieeTests/SparkRecordRecallTests \
  -only-testing:NotieeTests/SparkPromptRecallTests \
  -only-testing:NotieeTests/SparkViewModelTests \
  -only-testing:NotieeTests/SemanticSearchEngineTests \
  -only-testing:NotieeTests/SparkCitationStripTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 2: 两 scheme Release 构建**

Run: 两 scheme `xcodebuild build ... -configuration Debug` → 均 SUCCEEDED

- [ ] **Step 3: 手测四类查询（模拟器，>150 条记录）**

逐一确认：
1. 近期浏览「我最近记了啥」→ 命中锚点层，列出最近记录。
2. 时序梳理「帮我梳理这周」→ 锚点层足够，不被语义层干扰。
3. 老记录深挖（内容在第 150 条之外）「去年三月那个会议讲了啥」→ 语义层召回并**注入全文**答出细节。
4. 纯闲聊「今天天气不错」→ 正常闲聊，`[来源N]` 不乱标。
- **重点验引用不错位**：任一带 `[来源N]` 的回答，点开引用卡片必须是文中所指记录。

- [ ] **Step 4: 合回主干（等用户确认）**

```bash
git checkout main && git merge --ff-only feature/spark-semantic-recall
```

---

## Self-Review

**Spec 覆盖**（对照 `docs/Spark语义召回改造方案.md`）：
- §2 分层混合 → Task 1-3（merge/recall/两段渲染）✅
- §3 参数（15/8/0.45/800/20）→ Task 1 默认值 + Task 3 全文 800 截断 ✅
- §4.1 `ask` 注入语义 → Task 4/5 ✅
- §4.2 记录块分层 → Task 3 ✅
- §4.3 `[来源N]` 按 record.id 映射（最高风险）→ Task 5（专项测试）✅
- §4.4 冷启动回填 → Task 6 ✅
- §5 风险：引用错位（Task 5 测试）、本地向量兜底（锚点层不依赖向量，Task 3 结构保证）、加密不注入正文（Task 2 候选过滤 + Global Constraints）✅
- §7 Target 归属：全共享代码、无 `#if`，两 scheme 构建关卡（Task 2/4/5/6/7）✅

**占位符扫描**：每个 Task 均有具体代码与命令，无 TBD/TODO。

**类型一致性**：`RecalledRecords`(records/semanticStartIndex)、`SparkRecordRecall`(merge/recall/engine/anchorCount)、`ask(question:recall:recentRounds:upcomingEvents:)`、`buildSystemPrompt(recall:...)`、`liveForSpark(settingsStore:)`、`SemanticSearching`(search/backfill) 在各 Task 间一致。

**已知需实现者临场决策的点**（已在对应 Task 标注）：
- Task 5 Step 1：若无「发送并等待」测试助手，优先把 citation 计算抽成纯函数 `mapCitations(text:records:)` 直接单测（更稳）。
- `NoteRecord` 初始化器可选参数集合以实际定义为准（`summary`/`detailedContent`/`isEncrypted` 若非 init 参数则构造后赋值）。
