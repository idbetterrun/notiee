# RAG 语义检索 + 「所有待办」入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 Spark Agent 的拍记搜索加入混合语义检索（本地为主 + 云端可选），并在「我」页新增「所有待办」完整管理入口，Today 保持精简概览。

**Architecture:** Part A 通过 `EmbeddingService` 协议 + 旁路 `EmbeddingIndex` + `SemanticRanker`（关键词保底 + 阈值）实现，封装进 `SemanticSearchEngine` 后注入 `NoteSearchTool`；云端经 `HybridEmbeddingService` 带降级链接入。Part B 仿照现有 `AllSchedulesView` 范式新增 `AllTodosView`，复用已有 store CRUD。

**Tech Stack:** Swift / SwiftUI / XCTest，Apple `NaturalLanguage`（NLEmbedding）、`CryptoKit`（内容哈希），OpenAI 兼容 embeddings 接口。

---

## 前置说明（实现者必读）

- **Xcode 工程使用 `PBXFileSystemSynchronizedRootGroup`**：把新 `.swift` 文件放进 `Notiee/`（源码）或 `NotieeTests/`（测试）对应目录即自动加入 target，**无需手改 `.pbxproj`**。
- **运行单个测试类的命令**（全程统一）：
  ```bash
  xcodebuild -project Notiee.xcodeproj -scheme Notiee \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
    test -only-testing:NotieeTests/<测试类名> 2>&1 | tail -20
  ```
  期望末尾出现 `** TEST SUCCEEDED **`（或单测 `Test Suite ... passed`）。失败时出现 `** TEST FAILED **`。
- **测试风格**：`import XCTest` + `@testable import Notiee`，`final class XxxTests: XCTestCase`；涉及 `@MainActor` 类型的测试类加 `@MainActor`（参考 `NotieeTests/TodayViewModelTests.swift`）。
- **当前分支**：`feature/rag-and-all-todos`。提交频繁、每个任务一提交。
- 之前已修复并仍在工作区未提交的三处（Agent 数据回传 / Today 待办过滤 / 圆形按钮）属于另一批改动，本计划不依赖也不覆盖它们。

## 文件结构总览

新增（Part A）：
- `Notiee/Services/Semantic/VectorMath.swift` — 余弦相似度纯函数
- `Notiee/Services/Semantic/EmbeddingService.swift` — 协议 + 错误 + 文本组装/哈希
- `Notiee/Services/Semantic/EmbeddingIndex.swift` — 向量旁路持久化
- `Notiee/Services/Semantic/SemanticRanker.swift` — 混合排序
- `Notiee/Services/Semantic/LocalEmbeddingService.swift` — NLEmbedding 实现
- `Notiee/Services/Semantic/CloudEmbeddingService.swift` — 云端实现
- `Notiee/Services/Semantic/HybridEmbeddingService.swift` — 选择 + 降级
- `Notiee/Services/Semantic/SemanticSearchEngine.swift` — 懒补算 + 排序协调器

修改（Part A）：
- `Notiee/Services/AIAPIClient.swift` — 新增 `OpenAICaller.callEmbedding`
- `Notiee/Features/Spark/Agent/Tools/NoteSearchTool.swift` — 注入可选引擎
- `Notiee/Features/Spark/SparkViewModel.swift` — 装配引擎
- `Notiee/Features/Settings/LabFeaturesView.swift` — 云端检索开关

新增（Part B）：
- `Notiee/Features/Today/TodoBucketer.swift` — 截止日分桶纯逻辑
- `Notiee/Features/Settings/AllTodosView.swift` — 全量待办页

修改（Part B）：
- `Notiee/Features/Today/TodayViewModel.swift` — 概览过滤
- `Notiee/Features/Today/TodayView.swift` — 「全部待办 →」入口
- `Notiee/Features/Settings/MeView.swift` — 「所有待办」入口

测试：上述每个含逻辑的组件对应一个 `NotieeTests/XxxTests.swift`。

---

# Part A — 混合语义检索（RAG）

## Task A1：余弦相似度

**Files:**
- Create: `Notiee/Services/Semantic/VectorMath.swift`
- Test: `NotieeTests/VectorMathTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import Notiee

final class VectorMathTests: XCTestCase {
    func testIdenticalVectors_similarityIsOne() {
        let v: [Float] = [1, 2, 3]
        XCTAssertEqual(VectorMath.cosineSimilarity(v, v), 1.0, accuracy: 1e-5)
    }

    func testOrthogonalVectors_similarityIsZero() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 0], [0, 1]), 0.0, accuracy: 1e-5)
    }

    func testOppositeVectors_similarityIsMinusOne() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 0], [-1, 0]), -1.0, accuracy: 1e-5)
    }

    func testMismatchedOrEmpty_returnsZero() {
        XCTAssertEqual(VectorMath.cosineSimilarity([1, 2], [1, 2, 3]), 0.0)
        XCTAssertEqual(VectorMath.cosineSimilarity([], []), 0.0)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `xcodebuild ... test -only-testing:NotieeTests/VectorMathTests`
Expected: 编译失败 / FAIL（`VectorMath` 未定义）

- [ ] **Step 3: 实现**

```swift
import Foundation

enum VectorMath {
    /// 余弦相似度。长度不一致或空向量返回 0（视为不相关）。
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard !a.isEmpty, a.count == b.count else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: 提交**

```bash
git add Notiee/Services/Semantic/VectorMath.swift NotieeTests/VectorMathTests.swift
git commit -m "feat(rag): cosine similarity vector math"
```

---

## Task A2：EmbeddingService 协议 + 文本组装/哈希

**Files:**
- Create: `Notiee/Services/Semantic/EmbeddingService.swift`
- Test: `NotieeTests/RecordEmbeddingTextTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import Notiee

final class RecordEmbeddingTextTests: XCTestCase {
    private func record(title: String, summary: String, ocr: String) -> NoteRecord {
        var r = NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
        r.summary = summary
        r.ocrText = ocr
        return r
    }

    func testCompose_joinsTitleSummaryOcr() {
        let text = RecordEmbeddingText.compose(record(title: "机器学习", summary: "梯度下降", ocr: "loss"))
        XCTAssertTrue(text.contains("机器学习"))
        XCTAssertTrue(text.contains("梯度下降"))
        XCTAssertTrue(text.contains("loss"))
    }

    func testCompose_truncatesToMaxLength() {
        let long = String(repeating: "字", count: 5000)
        let text = RecordEmbeddingText.compose(record(title: long, summary: "", ocr: ""))
        XCTAssertLessThanOrEqual(text.count, RecordEmbeddingText.maxLength)
    }

    func testContentHash_isStableAndSensitive() {
        XCTAssertEqual(RecordEmbeddingText.contentHash("abc"), RecordEmbeddingText.contentHash("abc"))
        XCTAssertNotEqual(RecordEmbeddingText.contentHash("abc"), RecordEmbeddingText.contentHash("abd"))
    }
}
```

> 注：若 `NoteRecord` 的 `summary` / `ocrText` 不是 `var` 或初始化签名不同，按 `Notiee/Models/NoteRecord.swift` 的真实定义调整测试里的构造方式（仅测试代码，逻辑不变）。

- [ ] **Step 2: 运行测试，确认失败**

Expected: 编译失败（`RecordEmbeddingText` / `EmbeddingService` 未定义）

- [ ] **Step 3: 实现**

```swift
import Foundation
import CryptoKit

/// 语义向量服务抽象。无法计算时抛错，由上层降级处理。
protocol EmbeddingService: Sendable {
    /// 模型标识，写入索引用于失效判断。
    var modelIdentifier: String { get }
    func embed(_ text: String) async throws -> [Float]
}

enum EmbeddingError: LocalizedError {
    case unavailable          // 引擎在本设备/语言不可用
    case cannotEmbed          // 文本无法编码
    case notConfigured        // 云端未配置
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "语义向量引擎不可用"
        case .cannotEmbed: return "无法对文本计算向量"
        case .notConfigured: return "云端向量未配置"
        case .requestFailed(let m): return "向量请求失败：\(m)"
        }
    }
}

/// 把一条拍记拼成用于 embedding 的文本，并提供内容哈希。
enum RecordEmbeddingText {
    static let maxLength = 2000

    static func compose(_ record: NoteRecord) -> String {
        let joined = [record.title, record.summary, record.ocrText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return String(joined.prefix(maxLength))
    }

    /// SHA256 十六进制，跨进程稳定（不可用 hashValue）。
    static func contentHash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

- [ ] **Step 5: 提交**

```bash
git add Notiee/Services/Semantic/EmbeddingService.swift NotieeTests/RecordEmbeddingTextTests.swift
git commit -m "feat(rag): EmbeddingService protocol + record text/hash helpers"
```

---

## Task A3：EmbeddingIndex 旁路持久化

**Files:**
- Create: `Notiee/Services/Semantic/EmbeddingIndex.swift`
- Test: `NotieeTests/EmbeddingIndexTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import Notiee

final class EmbeddingIndexTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("emb-\(UUID()).json")
    }

    func testSetGet_roundTrips() {
        let url = tmpURL()
        let index = EmbeddingIndex(fileURL: url)
        let id = UUID()
        let entry = EmbeddingEntry(vector: [0.1, 0.2], model: "m1", contentHash: "h1")
        index.set(entry, for: id)
        XCTAssertEqual(index.entry(for: id), entry)
    }

    func testPersistenceAcrossInstances() {
        let url = tmpURL()
        let id = UUID()
        let a = EmbeddingIndex(fileURL: url)
        a.set(EmbeddingEntry(vector: [1, 2, 3], model: "m1", contentHash: "h1"), for: id)
        let b = EmbeddingIndex(fileURL: url)
        XCTAssertEqual(b.entry(for: id)?.vector, [1, 2, 3])
    }

    func testRemove() {
        let url = tmpURL()
        let index = EmbeddingIndex(fileURL: url)
        let id = UUID()
        index.set(EmbeddingEntry(vector: [1], model: "m", contentHash: "h"), for: id)
        index.remove(id: id)
        XCTAssertNil(index.entry(for: id))
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

- [ ] **Step 3: 实现**

```swift
import Foundation

struct EmbeddingEntry: Codable, Equatable, Sendable {
    let vector: [Float]
    let model: String
    let contentHash: String
}

/// 拍记向量的旁路存储。与 NoteRecord JSON 解耦，可独立重算/失效。
@MainActor
final class EmbeddingIndex {
    private let fileURL: URL
    private var entries: [UUID: EmbeddingEntry]

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([UUID: EmbeddingEntry].self, from: data) {
            self.entries = decoded
        } else {
            self.entries = [:]
        }
    }

    func entry(for id: UUID) -> EmbeddingEntry? { entries[id] }

    func set(_ entry: EmbeddingEntry, for id: UUID) {
        entries[id] = entry
        save()
    }

    func remove(id: UUID) {
        entries[id] = nil
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// 默认位置：Application Support/embedding-index.json
    static let live: EmbeddingIndex = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return EmbeddingIndex(fileURL: dir.appendingPathComponent("embedding-index.json"))
    }()
}
```

- [ ] **Step 4: 运行测试，确认通过**

- [ ] **Step 5: 提交**

```bash
git add Notiee/Services/Semantic/EmbeddingIndex.swift NotieeTests/EmbeddingIndexTests.swift
git commit -m "feat(rag): EmbeddingIndex sidecar persistence"
```

---

## Task A4：SemanticRanker 混合排序（核心价值）

**Files:**
- Create: `Notiee/Services/Semantic/SemanticRanker.swift`
- Test: `NotieeTests/SemanticRankerTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import Notiee

final class SemanticRankerTests: XCTestCase {
    private func rec(_ title: String) -> NoteRecord {
        NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
    }

    func testSemanticMatch_includedAboveThreshold_evenWithoutKeyword() {
        let ranker = SemanticRanker(threshold: 0.5)
        let r = rec("深度学习")                       // 不含「机器学习」字面
        let out = ranker.rank(
            queryVector: [1, 0], queryText: "机器学习",
            candidates: [(r, [0.9, 0.1])],            // 与 query 高度相似
            limit: 5
        )
        XCTAssertEqual(out.map { $0.id }, [r.id])
    }

    func testBelowThreshold_excluded() {
        let ranker = SemanticRanker(threshold: 0.8)
        let r = rec("量子计算")
        let out = ranker.rank(
            queryVector: [1, 0], queryText: "机器学习",
            candidates: [(r, [0, 1])],                // 正交，相似度 0
            limit: 5
        )
        XCTAssertTrue(out.isEmpty)
    }

    func testKeywordHit_alwaysIncludedAndRankedFirst() {
        let ranker = SemanticRanker(threshold: 0.8)
        let kw = rec("机器学习导论")                  // 字面命中
        let sem = rec("深度学习")
        let out = ranker.rank(
            queryVector: [1, 0], queryText: "机器学习",
            candidates: [(sem, [0.95, 0.05]), (kw, [0, 1])],  // 关键词项语义为 0
            limit: 5
        )
        XCTAssertEqual(out.first?.id, kw.id, "关键词命中应排在最前")
        XCTAssertTrue(out.contains { $0.id == kw.id })
    }

    func testNilQueryVector_fallsBackToKeywordOnly() {
        let ranker = SemanticRanker(threshold: 0.5)
        let kw = rec("机器学习")
        let other = rec("烹饪")
        let out = ranker.rank(
            queryVector: nil, queryText: "机器学习",
            candidates: [(kw, nil), (other, nil)],
            limit: 5
        )
        XCTAssertEqual(out.map { $0.id }, [kw.id])
    }

    func testRespectsLimit() {
        let ranker = SemanticRanker(threshold: 0.0)
        let cands = (0..<10).map { (rec("机器学习\($0)"), [Float(1), 0]) }
        let out = ranker.rank(queryVector: [1, 0], queryText: "机器学习", candidates: cands, limit: 3)
        XCTAssertEqual(out.count, 3)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

- [ ] **Step 3: 实现**

```swift
import Foundation

/// 关键词保底 + 语义阈值的混合排序。纯逻辑、可确定性单测。
struct SemanticRanker {
    let threshold: Float

    init(threshold: Float = 0.45) {
        self.threshold = threshold
    }

    func rank(
        queryVector: [Float]?,
        queryText: String,
        candidates: [(record: NoteRecord, vector: [Float]?)],
        limit: Int
    ) -> [NoteRecord] {
        let q = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        struct Scored { let record: NoteRecord; let score: Float }
        var scored: [Scored] = []

        for c in candidates {
            let keywordHit = matchesKeyword(c.record, query: q)
            let sim: Float = {
                guard let qv = queryVector, let v = c.vector else { return 0 }
                return VectorMath.cosineSimilarity(qv, v)
            }()

            // 关键词命中始终纳入，并加 1.0 让其稳压纯语义项；否则需达到阈值。
            if keywordHit {
                scored.append(Scored(record: c.record, score: sim + 1.0))
            } else if queryVector != nil, sim >= threshold {
                scored.append(Scored(record: c.record, score: sim))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.record }
    }

    private func matchesKeyword(_ r: NoteRecord, query: String) -> Bool {
        guard !query.isEmpty else { return false }
        return r.title.localizedCaseInsensitiveContains(query)
            || r.summary.localizedCaseInsensitiveContains(query)
            || r.ocrText.localizedCaseInsensitiveContains(query)
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

- [ ] **Step 5: 提交**

```bash
git add Notiee/Services/Semantic/SemanticRanker.swift NotieeTests/SemanticRankerTests.swift
git commit -m "feat(rag): hybrid semantic ranker (keyword floor + threshold)"
```

---

## Task A5：LocalEmbeddingService（NLEmbedding）

**Files:**
- Create: `Notiee/Services/Semantic/LocalEmbeddingService.swift`
- Test: `NotieeTests/LocalEmbeddingServiceTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import Notiee

final class LocalEmbeddingServiceTests: XCTestCase {
    func testEnglishSentence_returnsNonEmptyVector_orSkipsIfUnavailable() async throws {
        let svc = LocalEmbeddingService()
        do {
            let v = try await svc.embed("machine learning is fun")
            XCTAssertFalse(v.isEmpty)
        } catch EmbeddingError.unavailable {
            throw XCTSkip("本设备无可用的 NLEmbedding 句向量模型")
        }
    }

    func testModelIdentifierIsStable() {
        XCTAssertEqual(LocalEmbeddingService().modelIdentifier, "nlembedding-sentence-v1")
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

- [ ] **Step 3: 实现**

```swift
import Foundation
import NaturalLanguage

/// 端上句向量。优先简体中文，回退英文；都不可用则抛 .unavailable（上层降级到关键词）。
final class LocalEmbeddingService: EmbeddingService {
    let modelIdentifier = "nlembedding-sentence-v1"

    func embed(_ text: String) async throws -> [Float] {
        let embedding = NLEmbedding.sentenceEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.sentenceEmbedding(for: .english)
        guard let embedding else { throw EmbeddingError.unavailable }
        guard let vec = embedding.vector(for: text) else { throw EmbeddingError.cannotEmbed }
        return vec.map { Float($0) }
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**（不可用时记为 skip 也算通过）

- [ ] **Step 5: 提交**

```bash
git add Notiee/Services/Semantic/LocalEmbeddingService.swift NotieeTests/LocalEmbeddingServiceTests.swift
git commit -m "feat(rag): on-device NLEmbedding service"
```

---

## Task A6：SemanticSearchEngine（懒补算 + 排序协调器）

**Files:**
- Create: `Notiee/Services/Semantic/SemanticSearchEngine.swift`
- Test: `NotieeTests/SemanticSearchEngineTests.swift`

- [ ] **Step 1: 写失败测试**（用 mock embedding 保证确定性）

```swift
import XCTest
@testable import Notiee

/// 把指定文本映射到指定向量；其余返回零向量。
private final class StubEmbeddingService: EmbeddingService {
    let modelIdentifier = "stub-v1"
    let table: [String: [Float]]
    init(_ table: [String: [Float]]) { self.table = table }
    func embed(_ text: String) async throws -> [Float] {
        for (k, v) in table where text.contains(k) { return v }
        return [0, 0]
    }
}

@MainActor
final class SemanticSearchEngineTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("emb-\(UUID()).json")
    }
    private func rec(_ title: String) -> NoteRecord {
        NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: title)
    }

    func testSemanticSearch_findsNonKeywordMatch() async {
        let stub = StubEmbeddingService(["机器学习": [1, 0], "深度学习": [0.95, 0.05]])
        let engine = SemanticSearchEngine(
            embeddingService: stub, index: EmbeddingIndex(fileURL: tmpURL()), threshold: 0.5
        )
        let r = rec("深度学习")
        let out = await engine.search(query: "机器学习", in: [r], limit: 5)
        XCTAssertEqual(out.map { $0.id }, [r.id])
    }

    func testEmbeddingCached_secondSearchReusesIndex() async {
        let index = EmbeddingIndex(fileURL: tmpURL())
        let stub = StubEmbeddingService(["机器学习": [1, 0], "深度学习": [0.9, 0.1]])
        let engine = SemanticSearchEngine(embeddingService: stub, index: index, threshold: 0.5)
        let r = rec("深度学习")
        _ = await engine.search(query: "机器学习", in: [r], limit: 5)
        XCTAssertNotNil(index.entry(for: r.id), "首次搜索后应缓存向量")
    }

    func testEmbeddingFailure_fallsBackToKeyword() async {
        final class FailingService: EmbeddingService {
            let modelIdentifier = "fail"
            func embed(_ text: String) async throws -> [Float] { throw EmbeddingError.unavailable }
        }
        let engine = SemanticSearchEngine(
            embeddingService: FailingService(), index: EmbeddingIndex(fileURL: tmpURL()), threshold: 0.5
        )
        let kw = rec("机器学习")
        let other = rec("烹饪")
        let out = await engine.search(query: "机器学习", in: [kw, other], limit: 5)
        XCTAssertEqual(out.map { $0.id }, [kw.id], "向量不可用时退化为关键词")
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

- [ ] **Step 3: 实现**

```swift
import Foundation

/// 协调：为候选拍记懒补算/复用向量 → 调用 SemanticRanker 排序。
@MainActor
final class SemanticSearchEngine {
    private let embeddingService: EmbeddingService
    private let index: EmbeddingIndex
    private let ranker: SemanticRanker

    init(embeddingService: EmbeddingService, index: EmbeddingIndex, threshold: Float = 0.45) {
        self.embeddingService = embeddingService
        self.index = index
        self.ranker = SemanticRanker(threshold: threshold)
    }

    func search(query: String, in records: [NoteRecord], limit: Int) async -> [NoteRecord] {
        // 1. query 向量（失败则 nil → ranker 走关键词保底）
        let queryVector = try? await embeddingService.embed(query)

        // 2. 为每条候选拿到当前向量（缺失/过期则补算）
        var candidates: [(record: NoteRecord, vector: [Float]?)] = []
        for record in records {
            let vector = await ensureVector(for: record)
            candidates.append((record, vector))
        }

        return ranker.rank(queryVector: queryVector, queryText: query, candidates: candidates, limit: limit)
    }

    /// 后台回填（启动时可调用）。失败的单条跳过，不影响整体。
    func backfill(records: [NoteRecord]) async {
        for record in records { _ = await ensureVector(for: record) }
    }

    private func ensureVector(for record: NoteRecord) async -> [Float]? {
        let text = RecordEmbeddingText.compose(record)
        guard !text.isEmpty else { return nil }
        let hash = RecordEmbeddingText.contentHash(text)

        if let existing = index.entry(for: record.id),
           existing.contentHash == hash,
           existing.model == embeddingService.modelIdentifier {
            return existing.vector
        }

        guard let vector = try? await embeddingService.embed(text) else { return nil }
        index.set(EmbeddingEntry(vector: vector, model: embeddingService.modelIdentifier, contentHash: hash), for: record.id)
        return vector
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

- [ ] **Step 5: 提交**

```bash
git add Notiee/Services/Semantic/SemanticSearchEngine.swift NotieeTests/SemanticSearchEngineTests.swift
git commit -m "feat(rag): semantic search engine (lazy embed + cache + fallback)"
```

---

## Task A7：接入 NoteSearchTool

**Files:**
- Modify: `Notiee/Features/Spark/Agent/Tools/NoteSearchTool.swift`
- Test: `NotieeTests/NoteSearchToolTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import Notiee

@MainActor
final class NoteSearchToolTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID()).json")
    }
    private func makeManager(_ titles: [String]) -> RecordManager {
        let records = titles.map { NoteRecord(id: UUID(), capturedAt: Date(), localImagePaths: ["x"], title: $0) }
        return RecordManager(records: records, todos: [], recordStore: JSONNoteRecordStore(fileURL: tmpURL()))
    }

    func testWithEngine_returnsSemanticMatch() async throws {
        final class StubEngine: SemanticSearching {
            let hitTitle: String
            init(_ t: String) { hitTitle = t }
            func search(query: String, in records: [NoteRecord], limit: Int) async -> [NoteRecord] {
                records.filter { $0.title == hitTitle }
            }
        }
        let mgr = makeManager(["深度学习", "烹饪"])
        let tool = NoteSearchTool(recordManager: mgr, searchEngine: StubEngine("深度学习"))
        let result = try await tool.execute(parameters: ["query": "机器学习"])
        let records = (result.data?["records"] as? [[String: Any]]) ?? []
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?["title"] as? String, "深度学习")
    }

    func testWithoutEngine_keywordPathUnchanged() async throws {
        let mgr = makeManager(["机器学习导论", "烹饪"])
        let tool = NoteSearchTool(recordManager: mgr, searchEngine: nil)
        let result = try await tool.execute(parameters: ["query": "机器学习"])
        let records = (result.data?["records"] as? [[String: Any]]) ?? []
        XCTAssertEqual(records.map { $0["title"] as? String }, ["机器学习导论"])
    }
}
```

> 若 `RecordManager` 构造签名与此不同，参照 `NotieeTests/RecordManagerTests.swift` 调整（仅测试代码）。

- [ ] **Step 2: 运行测试，确认失败**

- [ ] **Step 3: 实现** — 给工具加可选引擎依赖，并定义一个窄协议便于测试

在 `NoteSearchTool.swift` 顶部新增协议，并改造类：

```swift
import Foundation

/// 让工具可注入真引擎或测试桩。
@MainActor
protocol SemanticSearching {
    func search(query: String, in records: [NoteRecord], limit: Int) async -> [NoteRecord]
}

extension SemanticSearchEngine: SemanticSearching {}

@MainActor
final class NoteSearchTool: AgentTool {
    let name = "note_search"
    let description = "在用户的所有拍记中搜索相关内容。支持关键词与语义检索。返回匹配的记录列表及其摘要。"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "query": AgentToolProperty(type: "string", description: "搜索关键词或自然语言查询。越具体越好。", enumValues: nil, items: nil),
            "time_range": AgentToolProperty(type: "string", description: "时间范围限定", enumValues: ["today", "this_week", "this_month", "half_year", "one_year", "all"], items: nil),
            "limit": AgentToolProperty(type: "number", description: "最大返回条数，默认5条", enumValues: nil, items: nil)
        ],
        required: ["query"]
    )

    let recordManager: RecordManager
    private let searchEngine: SemanticSearching?

    init(recordManager: RecordManager, searchEngine: SemanticSearching? = nil) {
        self.recordManager = recordManager
        self.searchEngine = searchEngine
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let query = parameters["query"] as? String else {
            throw AgentToolError.missingParameter("query")
        }
        let limit = (parameters["limit"] as? Int) ?? 5
        let timeRangeStr = parameters["time_range"] as? String

        var records = recordManager.sortedRecords
        if let range = timeRangeStr {
            records = filterByTimeRange(records, range)
        }

        let results: [NoteRecord]
        if let engine = searchEngine {
            results = await engine.search(query: query, in: records, limit: limit)
        } else {
            let queryLower = query.lowercased()
            let candidates = records.filter {
                $0.title.localizedCaseInsensitiveContains(queryLower)
                    || $0.summary.localizedCaseInsensitiveContains(queryLower)
                    || $0.ocrText.localizedCaseInsensitiveContains(queryLower)
            }
            results = Array(candidates.prefix(limit))
        }

        let recordsData = results.enumerated().map { i, record -> [String: Any] in
            [
                "index": i + 1,
                "record_id": record.id.uuidString,
                "title": record.title,
                "captured_at": record.capturedAt.ISO8601Format(),
                "summary": String(record.summary.prefix(200)),
                "is_favorite": record.isFavorite
            ]
        }

        let message = results.isEmpty
            ? "未找到与「\(query)」相关的拍记。"
            : "找到 \(results.count) 条与「\(query)」相关的拍记：\n"
                + results.enumerated().map { "  [记录\($0+1)] \($1.title) (\($1.capturedAt.formatted(date: .abbreviated, time: .shortened)))" }.joined(separator: "\n")

        return AgentToolResult(success: true, message: message, data: ["records": recordsData], undoAction: nil)
    }

    private func filterByTimeRange(_ records: [NoteRecord], _ range: String) -> [NoteRecord] {
        let now = Date()
        let calendar = Calendar.current
        let start: Date?
        switch range {
        case "today": start = calendar.startOfDay(for: now)
        case "this_week": start = calendar.date(byAdding: .day, value: -7, to: now)
        case "this_month": start = calendar.date(byAdding: .month, value: -1, to: now)
        case "half_year": start = calendar.date(byAdding: .month, value: -6, to: now)
        case "one_year": start = calendar.date(byAdding: .year, value: -1, to: now)
        default: return records
        }
        guard let s = start else { return records }
        return records.filter { $0.capturedAt >= s }
    }
}
```

> 注意：原文件末尾的 `enum AgentToolError { ... }` 定义**保持不动**（不要删除），只替换 `NoteSearchTool` 类体并在文件顶部加入 `SemanticSearching` 协议与 `extension`。

- [ ] **Step 4: 运行测试，确认通过**

- [ ] **Step 5: 提交**

```bash
git add Notiee/Features/Spark/Agent/Tools/NoteSearchTool.swift NotieeTests/NoteSearchToolTests.swift
git commit -m "feat(rag): wire semantic engine into note_search (keyword fallback intact)"
```

---

## Task A8：HybridEmbeddingService + 云端实现 + 设置开关 + 装配

**Files:**
- Modify: `Notiee/Services/AIAPIClient.swift`（新增 `callEmbedding`）
- Create: `Notiee/Services/Semantic/CloudEmbeddingService.swift`
- Create: `Notiee/Services/Semantic/HybridEmbeddingService.swift`
- Modify: `Notiee/Features/Spark/SparkViewModel.swift`（装配）
- Modify: `Notiee/Features/Settings/LabFeaturesView.swift`（开关）
- Test: `NotieeTests/HybridEmbeddingServiceTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import Notiee

final class HybridEmbeddingServiceTests: XCTestCase {
    private final class Tagged: EmbeddingService {
        let modelIdentifier: String
        let value: [Float]
        let shouldThrow: Bool
        init(_ id: String, _ v: [Float], throws t: Bool = false) { modelIdentifier = id; value = v; shouldThrow = t }
        func embed(_ text: String) async throws -> [Float] {
            if shouldThrow { throw EmbeddingError.requestFailed("boom") }
            return value
        }
    }

    func testPrefersCloudWhenEnabled() async throws {
        let h = HybridEmbeddingService(local: Tagged("local", [1]), cloud: Tagged("cloud", [2]), preferCloud: { true })
        let v = try await h.embed("x")
        XCTAssertEqual(v, [2])
    }

    func testUsesLocalWhenDisabled() async throws {
        let h = HybridEmbeddingService(local: Tagged("local", [1]), cloud: Tagged("cloud", [2]), preferCloud: { false })
        XCTAssertEqual(try await h.embed("x"), [1])
    }

    func testCloudFailure_fallsBackToLocal() async throws {
        let h = HybridEmbeddingService(local: Tagged("local", [1]), cloud: Tagged("cloud", [2], throws: true), preferCloud: { true })
        XCTAssertEqual(try await h.embed("x"), [1])
    }

    func testNoCloud_usesLocal() async throws {
        let h = HybridEmbeddingService(local: Tagged("local", [9]), cloud: nil, preferCloud: { true })
        XCTAssertEqual(try await h.embed("x"), [9])
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

- [ ] **Step 3a: 实现 HybridEmbeddingService**

`Notiee/Services/Semantic/HybridEmbeddingService.swift`：

```swift
import Foundation

/// 选择策略 + 降级链：云端（开关开 && 配置全）→ 本地。
final class HybridEmbeddingService: EmbeddingService {
    private let local: EmbeddingService
    private let cloud: EmbeddingService?
    private let preferCloud: @Sendable () -> Bool

    init(local: EmbeddingService, cloud: EmbeddingService?, preferCloud: @escaping @Sendable () -> Bool) {
        self.local = local
        self.cloud = cloud
        self.preferCloud = preferCloud
    }

    var modelIdentifier: String {
        (preferCloud() ? cloud?.modelIdentifier : nil) ?? local.modelIdentifier
    }

    func embed(_ text: String) async throws -> [Float] {
        if preferCloud(), let cloud {
            if let v = try? await cloud.embed(text) { return v }
        }
        return try await local.embed(text)
    }
}
```

- [ ] **Step 3b: 实现 OpenAICaller.callEmbedding**

在 `Notiee/Services/AIAPIClient.swift` 的 `enum OpenAICaller { ... }` 内新增方法：

```swift
    /// OpenAI 兼容 embeddings 接口。endpoint 应指向 .../embeddings。
    static func callEmbedding(endpoint: String, model: String, apiKey: String, input: String) async throws -> [Float] {
        guard let url = URL(string: endpoint) else { throw AIError.apiError("Invalid URL") }
        let payload: [String: Any] = ["model": model, "input": input]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AIError.apiError("Unknown response") }
        if !(200...299).contains(http.statusCode) {
            throw AIError.apiError("Status \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]],
              let first = arr.first,
              let raw = first["embedding"] as? [Double] else {
            throw AIError.parsingFailed
        }
        return raw.map { Float($0) }
    }
```

- [ ] **Step 3c: 实现 CloudEmbeddingService**

`Notiee/Services/Semantic/CloudEmbeddingService.swift`：

```swift
import Foundation

/// 云端 embedding。复用 Spark 文本模型的 endpoint/key，将 chat 路径替换为 embeddings 路径。
final class CloudEmbeddingService: EmbeddingService {
    struct Config { let endpoint: String; let apiKey: String; let model: String }
    private let configProvider: @Sendable () -> Config?

    init(configProvider: @escaping @Sendable () -> Config?) {
        self.configProvider = configProvider
    }

    var modelIdentifier: String { "cloud-" + (configProvider()?.model ?? "unknown") }

    func embed(_ text: String) async throws -> [Float] {
        guard let cfg = configProvider(), !cfg.apiKey.isEmpty, !cfg.model.isEmpty else {
            throw EmbeddingError.notConfigured
        }
        return try await OpenAICaller.callEmbedding(
            endpoint: Self.embeddingsEndpoint(from: cfg.endpoint),
            model: cfg.model, apiKey: cfg.apiKey, input: text
        )
    }

    /// 把 chat completions 端点改写成 embeddings 端点。
    static func embeddingsEndpoint(from chatEndpoint: String) -> String {
        if chatEndpoint.contains("/chat/completions") {
            return chatEndpoint.replacingOccurrences(of: "/chat/completions", with: "/embeddings")
        }
        if chatEndpoint.contains("/completions") {
            return chatEndpoint.replacingOccurrences(of: "/completions", with: "/embeddings")
        }
        return chatEndpoint
    }
}
```

- [ ] **Step 4: 运行 Hybrid 测试，确认通过**

Run: `... test -only-testing:NotieeTests/HybridEmbeddingServiceTests`

- [ ] **Step 5: 装配进 SparkViewModel.makeAgentExecutor**

在 `Notiee/Features/Spark/SparkViewModel.swift` 的 `makeAgentExecutor()` 内，构造引擎并传给 `NoteSearchTool`。把：

```swift
        let tools: [any AgentTool] = [
            NoteSearchTool(recordManager: recordManager),
```

改为（其余 tools 不变）：

```swift
        let embeddingModel = UserDefaults.standard.string(forKey: "spark.semanticSearch.embeddingModel") ?? "text-embedding-3-small"
        let cloud = CloudEmbeddingService(configProvider: {
            let cfg = self.settingsStore.loadConfiguration(for: .text)
            return CloudEmbeddingService.Config(endpoint: cfg.activeEndpoint, apiKey: cfg.apiKey, model: embeddingModel)
        })
        let hybrid = HybridEmbeddingService(
            local: LocalEmbeddingService(),
            cloud: cloud,
            preferCloud: { UserDefaults.standard.bool(forKey: "spark.semanticSearch.useCloud") }
        )
        let searchEngine = SemanticSearchEngine(embeddingService: hybrid, index: .live)

        let tools: [any AgentTool] = [
            NoteSearchTool(recordManager: recordManager, searchEngine: searchEngine),
```

> `settingsStore` 已是 `SparkViewModel` 现有属性（同 `makeAgentExecutor` 中 `AgentTrustManager(settingsStore: settingsStore)` 用法一致）。若闭包捕获 `self` 报循环引用警告，改用 `[settingsStore] in`。

- [ ] **Step 6: 设置开关**

在 `Notiee/Features/Settings/LabFeaturesView.swift` 的表单中新增一个 Section（放在已有实验项之间，照搬其 `Toggle`/`@AppStorage` 写法）：

```swift
        Section("语义检索") {
            Toggle("高质量云端检索", isOn: $useCloudEmbedding)
            Text("默认在本机计算语义向量（离线、不外传）。开启后用你配置的 AI 服务商接口计算，检索更准但会把拍记文本发送到该服务。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
```

并在该 View 顶部加属性：

```swift
    @AppStorage("spark.semanticSearch.useCloud") private var useCloudEmbedding = false
```

> 若 `LabFeaturesView` 不是 `Form`/`List` 结构或没有现成 `@AppStorage` 范式，按文件实际结构把 Toggle 放到合适容器；key 必须与装配处一致：`spark.semanticSearch.useCloud`。

- [ ] **Step 7: 构建验证**

Run:
```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: 提交**

```bash
git add Notiee/Services/AIAPIClient.swift \
        Notiee/Services/Semantic/CloudEmbeddingService.swift \
        Notiee/Services/Semantic/HybridEmbeddingService.swift \
        Notiee/Features/Spark/SparkViewModel.swift \
        Notiee/Features/Settings/LabFeaturesView.swift \
        NotieeTests/HybridEmbeddingServiceTests.swift
git commit -m "feat(rag): hybrid local/cloud embedding with toggle + assemble into Spark"
```

---

# Part B — 「所有待办」入口

## Task B1：截止日分桶纯逻辑

**Files:**
- Create: `Notiee/Features/Today/TodoBucketer.swift`
- Test: `NotieeTests/TodoBucketerTests.swift`

- [ ] **Step 1: 写失败测试**

```swift
import XCTest
@testable import Notiee

final class TodoBucketerTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private func now() -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 23; c.hour = 10
        return cal.date(from: c)!
    }
    private func todo(due offsetDays: Int?) -> NoteTodo {
        let d = offsetDays.map { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: now()))! }
        return NoteTodo(recordID: nil, content: "t", dueDate: d)
    }

    func testBuckets() {
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: -1), now: now(), calendar: cal), .overdue)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: 0),  now: now(), calendar: cal), .today)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: 1),  now: now(), calendar: cal), .tomorrow)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: 4),  now: now(), calendar: cal), .thisWeek)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: 30), now: now(), calendar: cal), .later)
        XCTAssertEqual(TodoBucketer.bucket(for: todo(due: nil), now: now(), calendar: cal), .noDueDate)
    }

    func testIsActionableNow() {
        XCTAssertTrue(TodoBucketer.isActionableNow(todo(due: -1), now: now(), calendar: cal))  // overdue
        XCTAssertTrue(TodoBucketer.isActionableNow(todo(due: 0),  now: now(), calendar: cal))  // today
        XCTAssertTrue(TodoBucketer.isActionableNow(todo(due: nil), now: now(), calendar: cal)) // 无截止
        XCTAssertFalse(TodoBucketer.isActionableNow(todo(due: 3), now: now(), calendar: cal))  // 远期
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

- [ ] **Step 3: 实现**

```swift
import Foundation

enum TodoDueBucket: Int, CaseIterable {
    case overdue, today, tomorrow, thisWeek, later, noDueDate

    var title: String {
        switch self {
        case .overdue: return "已逾期"
        case .today: return "今天"
        case .tomorrow: return "明天"
        case .thisWeek: return "本周"
        case .later: return "更晚"
        case .noDueDate: return "无截止日期"
        }
    }
}

enum TodoBucketer {
    static func bucket(for todo: NoteTodo, now: Date = Date(), calendar: Calendar = .current) -> TodoDueBucket {
        guard let due = todo.dueDate else { return .noDueDate }
        let startToday = calendar.startOfDay(for: now)
        let startDue = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: startToday, to: startDue).day ?? 0
        if days < 0 { return .overdue }
        if days == 0 { return .today }
        if days == 1 { return .tomorrow }
        if days <= 7 { return .thisWeek }
        return .later
    }

    /// Today 概览：逾期 / 今天 / 无截止 视为「当下可执行」。
    static func isActionableNow(_ todo: NoteTodo, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch bucket(for: todo, now: now, calendar: calendar) {
        case .overdue, .today, .noDueDate: return true
        case .tomorrow, .thisWeek, .later: return false
        }
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

- [ ] **Step 5: 提交**

```bash
git add Notiee/Features/Today/TodoBucketer.swift NotieeTests/TodoBucketerTests.swift
git commit -m "feat(todos): due-date bucketing + actionable-now logic"
```

---

## Task B2：Today 概览过滤

**Files:**
- Modify: `Notiee/Features/Today/TodayViewModel.swift`
- Test: `NotieeTests/TodayViewModelTests.swift`（追加用例）

- [ ] **Step 1: 追加失败测试**

在 `TodayViewModelTests` 类内追加（参考文件已有 `temporaryFileURL()` / `referenceDate` 辅助；若没有就用 `FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json")` 和 `Date()`）：

```swift
    func testTodayOverview_showsActionableCapsAndHidesFarFuture() {
        let store = NotieeStore(
            currentDate: Date(), events: [], todos: [], records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )
        let cal = Calendar.current
        let far = cal.date(byAdding: .day, value: 10, to: Date())!
        store.addTodo(NoteTodo(recordID: nil, content: "无截止"))
        store.addTodo(NoteTodo(recordID: nil, content: "远期", dueDate: far))

        let vm = TodayViewModel(store: store)
        let contents = vm.todayOverviewTodos.map { $0.content }
        XCTAssertTrue(contents.contains("无截止"))
        XCTAssertFalse(contents.contains("远期"), "远期待办不进 Today 概览")
    }

    func testTodayOverview_capsAtMaxCount() {
        let store = NotieeStore(
            currentDate: Date(), events: [], todos: [], records: [],
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL())
        )
        for i in 0..<10 { store.addTodo(NoteTodo(recordID: nil, content: "无截止\(i)")) }
        let vm = TodayViewModel(store: store)
        XCTAssertLessThanOrEqual(vm.todayOverviewTodos.count, TodayViewModel.overviewTodoCap)
    }
```

- [ ] **Step 2: 运行测试，确认失败**

- [ ] **Step 3: 实现** — 在 `TodayViewModel` 的 `// MARK: - Todos` 区追加：

```swift
    static let overviewTodoCap = 5

    /// Today 概览：未完成 + 当下可执行（逾期/今天/无截止），按截止日升序，封顶。
    var todayOverviewTodos: [NoteTodo] {
        pendingTodos
            .filter { TodoBucketer.isActionableNow($0, now: currentDate, calendar: calendar) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(Self.overviewTodoCap)
            .map { $0 }
    }
```

> `pendingTodos`、`calendar`、`currentDate` 均为 `TodayViewModel` 既有成员。

- [ ] **Step 4: 运行测试，确认通过**

- [ ] **Step 5: 提交**

```bash
git add Notiee/Features/Today/TodayViewModel.swift NotieeTests/TodayViewModelTests.swift
git commit -m "feat(todos): Today actionable-now overview (capped)"
```

---

## Task B3：AllTodosView + MeView 入口 + Today 链接（UI）

**Files:**
- Create: `Notiee/Features/Settings/AllTodosView.swift`
- Modify: `Notiee/Features/Settings/MeView.swift`
- Modify: `Notiee/Features/Today/TodayView.swift`

> 本任务以 UI 为主，逻辑已被 B1/B2 单测覆盖；验收靠构建 + 模拟器目检。

- [ ] **Step 1: 创建 AllTodosView**

`Notiee/Features/Settings/AllTodosView.swift`：

```swift
import SwiftUI

struct AllTodosView: View {
    @ObservedObject var store: NotieeStore
    @State private var selectedTodo: NoteTodo?
    @State private var showCreate = false
    @State private var completedCollapsed = true

    private var pending: [NoteTodo] {
        store.todos.filter { !$0.isCompleted }
    }
    private var completed: [NoteTodo] {
        store.todos.filter { $0.isCompleted }.sorted { $0.createdAt > $1.createdAt }
    }

    private func grouped() -> [(bucket: TodoDueBucket, items: [NoteTodo])] {
        let groups = Dictionary(grouping: pending) { TodoBucketer.bucket(for: $0) }
        return TodoDueBucket.allCases.compactMap { bucket in
            guard let items = groups[bucket], !items.isEmpty else { return nil }
            let sorted = items.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            return (bucket, sorted)
        }
    }

    var body: some View {
        List {
            ForEach(grouped(), id: \.bucket.rawValue) { group in
                Section(group.bucket.title) {
                    ForEach(group.items) { todo in row(todo) }
                }
            }

            if !completed.isEmpty {
                Section {
                    if !completedCollapsed {
                        ForEach(completed) { todo in row(todo) }
                    }
                } header: {
                    Button {
                        withAnimation { completedCollapsed.toggle() }
                    } label: {
                        HStack {
                            Text("已完成 (\(completed.count))")
                            Spacer()
                            Image(systemName: completedCollapsed ? "chevron.right" : "chevron.down")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("所有待办")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $selectedTodo) { todo in
            TodoDetailSheetView(todo: todo, viewModel: TodayViewModel(store: store))
        }
        .sheet(isPresented: $showCreate) {
            CreateItemSheet(viewModel: TodayViewModel(store: store))
        }
    }

    private func row(_ todo: NoteTodo) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation { store.toggleTodo(id: todo.id) }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(todo.content)
                    .strikethrough(todo.isCompleted, color: .secondary)
                    .foregroundColor(todo.isCompleted ? .secondary : .primary)
                HStack(spacing: 8) {
                    if let due = todo.dueDate {
                        Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    if todo.hasReminder {
                        Image(systemName: "bell.fill").font(.caption2).foregroundColor(.orange)
                    }
                    if let rid = todo.recordID,
                       let rec = store.records.first(where: { $0.id == rid }) {
                        Label(rec.title, systemImage: "doc.text")
                            .font(.caption2).foregroundColor(.blue).lineLimit(1)
                    }
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedTodo = todo }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.deleteTodo(id: todo.id) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
```

> 校验点：`TodoDetailSheetView` 与 `CreateItemSheet` 的初始化签名需为 `(todo:viewModel:)` / `(viewModel:)`（与 `TodayView.swift` 现用法一致）。若签名不同，按其真实签名调整这两处 `.sheet`。

- [ ] **Step 2: MeView 新增入口** — 在 `Notiee/Features/Settings/MeView.swift` 「全部日程」所在 `Section` 内，紧接「全部日程」`NavigationLink` 之后插入：

```swift
                NavigationLink {
                    AllTodosView(store: store)
                } label: {
                    Label("所有待办", systemImage: "checklist")
                        .foregroundColor(NotieeColors.themed(.blue))
                }
```

- [ ] **Step 3: Today 接概览 + 全部待办链接** — 在 `Notiee/Features/Today/TodayView.swift` 的 `todoSection` 中：

  (a) 把列表数据源从 `viewModel.allTodos` 改为 `viewModel.todayOverviewTodos`：

```swift
            if viewModel.todayOverviewTodos.isEmpty {
                Text("AI 提取的待办会显示在这里。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ForEach(viewModel.todayOverviewTodos) { todo in
                    TodoRowView(todo: todo, onToggle: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.toggleTodo(id: todo.id)
                        }
                    }, onInfo: {
                        selectedTodo = todo
                    })
                }
            }
```

  (b) 在 `todoSection` 的标题 `HStack` 中，把计数徽标改为基于概览数，并在 `Spacer()` 后加「全部待办 →」`NavigationLink`。把标题 HStack 替换为：

```swift
            HStack(spacing: 8) {
                Text("待办事项")
                    .font(.title3.weight(.bold))

                Text("\(viewModel.pendingTodos.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(.blue, in: Circle())

                Spacer()

                if let store = viewModel.store {
                    NavigationLink {
                        AllTodosView(store: store)
                    } label: {
                        Text("全部待办 →").font(.subheadline).foregroundStyle(.blue)
                    }
                }
            }
```

- [ ] **Step 4: 构建验证**

Run:
```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: 模拟器目检（手动）**

启动 App → Today 待办区显示「当下可执行」概览 + 「全部待办 →」；点击进入 `AllTodosView`，按桶分组、可勾选/左滑删除/点击编辑/右上 `+` 新建；我 → 「所有待办」入口可达。

- [ ] **Step 6: 提交**

```bash
git add Notiee/Features/Settings/AllTodosView.swift \
        Notiee/Features/Settings/MeView.swift \
        Notiee/Features/Today/TodayView.swift
git commit -m "feat(todos): AllTodosView + Me entry + Today overview link"
```

---

## 收尾

- [ ] 跑一遍相关测试合集确认全绿：

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test -only-testing:NotieeTests/VectorMathTests \
       -only-testing:NotieeTests/RecordEmbeddingTextTests \
       -only-testing:NotieeTests/EmbeddingIndexTests \
       -only-testing:NotieeTests/SemanticRankerTests \
       -only-testing:NotieeTests/SemanticSearchEngineTests \
       -only-testing:NotieeTests/NoteSearchToolTests \
       -only-testing:NotieeTests/HybridEmbeddingServiceTests \
       -only-testing:NotieeTests/TodoBucketerTests \
       -only-testing:NotieeTests/TodayViewModelTests 2>&1 | tail -20
```

- [ ] 若计划作为分支收尾，参考 superpowers:finishing-a-development-branch 决定合并/PR。

---

## 范围之外（沿用 spec）

- 记录页手动搜索框接入语义检索（本期仅 Agent）。
- 内置 CoreML 多语言 embedding 模型（协议已预留，后续质量升级）。
- 启动时主动后台回填：`SemanticSearchEngine.backfill(records:)` 已实现，但本计划只走「搜索时懒补算」；如需启动回填，可在 app 启动处调用，属增量任务。
- 待办提醒/通知调度改造。

## 自检结论（写计划时已核对）

- **spec 覆盖**：Part A 的 EmbeddingService/Index/Ranker/Local/Cloud/Hybrid/Engine/工具接入/设置开关、Part B 的入口/AllTodosView/Today 精简，均有对应任务。
- **占位符**：无 TBD/TODO；每个改代码的步骤均含完整代码。
- **类型一致性**：`EmbeddingService.embed/modelIdentifier`、`EmbeddingEntry(vector/model/contentHash)`、`SemanticRanker.rank(queryVector:queryText:candidates:limit:)`、`SemanticSearchEngine.search(query:in:limit:)`、`SemanticSearching` 协议、`TodoBucketer.bucket/isActionableNow`、`TodayViewModel.todayOverviewTodos/overviewTodoCap` 在各任务间签名一致。
- **已知校验点**（实现时按真实定义核对，已在对应步骤标注）：`NoteRecord` 构造/字段是否为 `var`、`RecordManager` 构造签名、`TodoDetailSheetView`/`CreateItemSheet` 初始化签名、`LabFeaturesView` 容器结构。
