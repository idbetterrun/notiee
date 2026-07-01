# Notiee P0 缺陷修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复经代码核实确认的 8 个高危缺陷（数据丢失、密钥明文、路径穿越、索引/图片残留、向量误标、Agent 撤销失效），每个改动自成一体、可独立测试。

**Architecture:** 采用 TDD——先写失败测试、再最小实现。改动分布在持久化层（NotieeStore / JSON stores / NoteTodo）、图片/索引清理（LocalImageStore / RecordManager / EmbeddingIndex）、语义层（EmbeddingService / Hybrid / SemanticSearchEngine）、设置存储（UserDefaultsAppSettingsStore + Keychain）、导入（TMNImportService）、以及 Agent 撤销（AgentTool / 三个 delete 工具 / AgentExecutor）。不触碰更大的架构项（iCloud 同步重写、prompt 注入体系、信任模型），那些另立计划。

**Tech Stack:** Swift / SwiftUI，XCTest 单元测试，`@testable import Notiee`。测试目标 `NotieeTests`。

**运行测试的通用命令**（可在 Xcode 里跑，或命令行）：
```bash
xcodebuild test -scheme Notiee \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:NotieeTests/<TestClass>/<testMethod>
```
> 若模拟器名不匹配，先 `xcrun simctl list devices available` 选一个存在的机型替换 `name=`。

**对应审查报告条目：** Task 1↔#1、Task 2↔#1、Task 3↔#11、Task 4↔#10、Task 5↔#9、Task 6↔#2、Task 7↔#3、Task 8↔#7。

---

## File Structure

新建：
- `Notiee/Services/PersistenceRecovery.swift` — 解码失败时把损坏文件隔离备份、返回 nil 的通用助手（Task 2）。
- `Notiee/Features/Spark/Agent/Tools/NoteDeleteTool.swift` — 撤销专用删除工具，模型不可见（Task 8）。
- `Notiee/Features/Spark/Agent/Tools/TodoDeleteTool.swift` — 同上（Task 8）。
- `Notiee/Features/Spark/Agent/Tools/ScheduleDeleteTool.swift` — 同上（Task 8）。

修改：
- `Notiee/Models/NoteTodo.swift` — 加防御式 `init(from:)`（Task 1）。
- `Notiee/Services/NotieeStore.swift:400-415` — 用隔离助手替换 `(try? ...) ?? []`；接线索引清理回调（Task 2、Task 4）。
- `Notiee/Services/LocalImageStore.swift` — 新增 `deleteImage(path:)`（Task 3）。
- `Notiee/Services/Managers/RecordManager.swift` — 删除走 `LocalImageStore.deleteImage`；新增 `onRecordsDeleted` 回调（Task 3、Task 4）。
- `Notiee/Services/Semantic/EmbeddingService.swift` — 新增 `EmbeddingResult` 与 `embedTagged` 默认实现（Task 5）。
- `Notiee/Services/Semantic/HybridEmbeddingService.swift` — override `embedTagged` 返回真实来源模型（Task 5）。
- `Notiee/Services/Semantic/SemanticSearchEngine.swift:64-65` — 用 `embedTagged` 打标签（Task 5）。
- `Notiee/Services/UserDefaultsAppSettingsStore.swift:122-134` — 自定义模型 apiKey 走 Keychain（Task 6）。
- `Notiee/Services/TMNImportService.swift` — 归档内路径穿越校验（Task 7）。
- `Notiee/Features/Spark/Agent/AgentToolProtocol.swift` — 加 `visibleToModel` 默认属性（Task 8）。
- `Notiee/Features/Spark/Agent/AgentToolRegistry.swift:18-20` — `allTools` 过滤 `visibleToModel`（Task 8）。
- `Notiee/Features/Spark/Agent/AgentExecutor.swift:168-179` — 简化撤销、移除“解码后丢弃”死分支（Task 8）。
- `Notiee/Features/Spark/SparkViewModel.swift:520-539` — 注册三个 delete 工具（Task 8）。

新建测试：
- `NotieeTests/NoteTodoDecodingTests.swift`（Task 1）
- `NotieeTests/PersistenceRecoveryTests.swift`（Task 2）
- `NotieeTests/LocalImageStoreDeleteTests.swift`（Task 3）
- `NotieeTests/RecordDeletionHookTests.swift`（Task 4）
- 追加到 `NotieeTests/HybridEmbeddingServiceTests.swift`（Task 5）
- `NotieeTests/CustomModelKeychainTests.swift`（Task 6）
- 追加到 `NotieeTests/WebFetchToolTests.swift` 无关；新建 `NotieeTests/TMNPathSafetyTests.swift`（Task 7）
- `NotieeTests/AgentUndoDeleteToolsTests.swift`（Task 8）

---

## Task 1: NoteTodo 防御式解码（#1a）

**问题：** `NoteTodo` 用合成 Codable，`hasReminder`（非可选 Bool）等字段缺失时整个 todos 数组解码失败。与 `NoteRecord` 的 `decodeIfPresent` 不对称，schema 变更即触发数据丢失链。

**Files:**
- Modify: `Notiee/Models/NoteTodo.swift`
- Test: `NotieeTests/NoteTodoDecodingTests.swift`

- [ ] **Step 1: 写失败测试**

Create `NotieeTests/NoteTodoDecodingTests.swift`:

```swift
import XCTest
@testable import Notiee

final class NoteTodoDecodingTests: XCTestCase {
    /// 旧数据缺少 hasReminder / dueDate 字段时，仍应成功解码并回落到默认值。
    func testDecode_missingNewFields_usesDefaults() throws {
        let json = """
        { "id": "00000000-0000-0000-0000-000000000001",
          "content": "buy milk",
          "isCompleted": false,
          "createdAt": 0 }
        """.data(using: .utf8)!

        let todo = try JSONDecoder().decode(NoteTodo.self, from: json)

        XCTAssertEqual(todo.content, "buy milk")
        XCTAssertFalse(todo.hasReminder)
        XCTAssertNil(todo.dueDate)
    }

    /// 缺失 id 时生成新 id，而不是整条抛错。
    func testDecode_missingId_generatesId() throws {
        let json = #"{ "content": "x", "isCompleted": true, "createdAt": 0 }"#.data(using: .utf8)!
        let todo = try JSONDecoder().decode(NoteTodo.self, from: json)
        XCTAssertEqual(todo.content, "x")
        XCTAssertTrue(todo.isCompleted)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/NoteTodoDecodingTests`
Expected: FAIL —— `keyNotFound "hasReminder"`（合成解码要求全字段）。

- [ ] **Step 3: 加防御式 init(from:) 与显式 CodingKeys**

在 `Notiee/Models/NoteTodo.swift` 的 `init(...)` 之后、结构体闭合 `}` 之前插入：

```swift
    enum CodingKeys: String, CodingKey {
        case id, recordID, content, isCompleted, createdAt, dueDate, hasReminder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        recordID = try c.decodeIfPresent(UUID.self, forKey: .recordID)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate)
        hasReminder = try c.decodeIfPresent(Bool.self, forKey: .hasReminder) ?? false
    }
```

> `encode(to:)` 仍由编译器基于显式 `CodingKeys` 合成，无需手写；round-trip 不变。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。
Expected: PASS（两个用例）。

- [ ] **Step 5: 提交**

```bash
git add Notiee/Models/NoteTodo.swift NotieeTests/NoteTodoDecodingTests.swift
git commit -m "fix(todo): defensive NoteTodo decoding to survive schema additions

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: 解码失败隔离，杜绝“空数组覆写磁盘”（#1b）

**问题：** `NotieeStore.live` 用 `(try? store.loadX()) ?? []`——真正的解码错误被吞成空内存，下一次任意写入把空状态永久落盘。要区分“文件不存在（合法空）”与“解码失败（损坏）”。stores 对缺失/空文件已返回 `[]`，只在真错误时 `throw`；故只需在 `throw` 时把坏文件挪走备份、返回 nil。

**Files:**
- Create: `Notiee/Services/PersistenceRecovery.swift`
- Modify: `Notiee/Services/NotieeStore.swift:400-415`
- Test: `NotieeTests/PersistenceRecoveryTests.swift`

- [ ] **Step 1: 写失败测试**

Create `NotieeTests/PersistenceRecoveryTests.swift`:

```swift
import XCTest
@testable import Notiee

final class PersistenceRecoveryTests: XCTestCase {
    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("pr-\(UUID()).json")
    }

    func testLoad_success_returnsValueAndKeepsFile() throws {
        let url = tmpURL()
        try Data("ok".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let value = PersistenceRecovery.loadOrQuarantine(fileURL: url) { "decoded" }

        XCTAssertEqual(value, "decoded")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoad_throws_quarantinesFileAndReturnsNil() throws {
        let url = tmpURL()
        try Data("corrupt".utf8).write(to: url)

        struct Boom: Error {}
        let value: String? = PersistenceRecovery.loadOrQuarantine(fileURL: url) { throw Boom() }

        XCTAssertNil(value)
        // 原文件被移走（未被覆写/删除，字节仍在某个 .corrupt-* 里）。
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let siblings = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        XCTAssertTrue(siblings.contains { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".corrupt-") })
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/PersistenceRecoveryTests`
Expected: FAIL —— `PersistenceRecovery` 未定义。

- [ ] **Step 3: 实现助手**

Create `Notiee/Services/PersistenceRecovery.swift`:

```swift
import Foundation

/// 解码失败恢复：把可能损坏的持久化文件挪到 `<name>.corrupt-<timestamp>` 备份，
/// 而不是让上层拿到空数组去覆写磁盘——从而杜绝“解码失败 → 空状态落盘 → 数据永久丢失”。
enum PersistenceRecovery {
    /// 执行 `load`；抛错时把 `fileURL` 隔离备份并返回 nil。
    /// 调用方随后从空开始，但原始字节被保留、原路径不会被覆写。
    static func loadOrQuarantine<T>(fileURL: URL, load: () throws -> T) -> T? {
        do {
            return try load()
        } catch {
            quarantine(fileURL: fileURL)
            return nil
        }
    }

    static func quarantine(fileURL: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(stamp)")
        try? fm.moveItem(at: fileURL, to: dest)
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。
Expected: PASS。

- [ ] **Step 5: 接线 NotieeStore.live**

在 `Notiee/Services/NotieeStore.swift` 把这几行：

```swift
        let persistedRecords = (try? recordJSONStore.loadRecords()) ?? []
        let persistedTodos = (try? todoJSONStore.loadTodos()) ?? []
        let persistedFolders = (try? folderJSONStore.loadFolders()) ?? []
        let persistedTags = (try? tagJSONStore.loadTags()) ?? []
```

替换为：

```swift
        let persistedRecords = PersistenceRecovery.loadOrQuarantine(fileURL: recordJSONStore.fileURL) { try recordJSONStore.loadRecords() } ?? []
        let persistedTodos = PersistenceRecovery.loadOrQuarantine(fileURL: todoJSONStore.fileURL) { try todoJSONStore.loadTodos() } ?? []
        let persistedFolders = PersistenceRecovery.loadOrQuarantine(fileURL: folderJSONStore.fileURL) { try folderJSONStore.loadFolders() } ?? []
        let persistedTags = PersistenceRecovery.loadOrQuarantine(fileURL: tagJSONStore.fileURL) { try tagJSONStore.loadTags() } ?? []
```

再把：

```swift
        let customEvents = (try? eventJSONStore.loadEvents()) ?? []
```

替换为：

```swift
        let customEvents = PersistenceRecovery.loadOrQuarantine(fileURL: eventJSONStore.fileURL) { try eventJSONStore.loadEvents() } ?? []
```

> `fileURL` 在 `JSONNoteRecordStore` / `JSONNoteTodoStore` / `JSONCustomFolderStore` / `JSONEventTagStore` / `JSONScheduledEventStore` 上均为 `let fileURL: URL`（已核实）。

- [ ] **Step 6: 编译整库确认接线无误**

Run: `xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 7: 提交**

```bash
git add Notiee/Services/PersistenceRecovery.swift Notiee/Services/NotieeStore.swift NotieeTests/PersistenceRecoveryTests.swift
git commit -m "fix(store): quarantine corrupt persistence files instead of silently blanking

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: 图片能被真正删除（#11）

**问题：** `LocalImageStore.saveImage` 返回相对路径 `CapturedImages/x.jpg`，读取时按 Documents 目录解析；但 `RecordManager` 删除用 `FileManager.removeItem(atPath: path)`——`atPath:` 按当前工作目录解析相对路径，永远找不到文件，图片无限堆积。

**Files:**
- Modify: `Notiee/Services/LocalImageStore.swift`
- Modify: `Notiee/Services/Managers/RecordManager.swift:196-198,226-228`
- Test: `NotieeTests/LocalImageStoreDeleteTests.swift`

- [ ] **Step 1: 写失败测试**

Create `NotieeTests/LocalImageStoreDeleteTests.swift`:

```swift
import XCTest
import UIKit
@testable import Notiee

@MainActor
final class LocalImageStoreDeleteTests: XCTestCase {
    func testDeleteImage_removesFileSavedByStore() throws {
        // 用真实 saveImage 写一张 1x1 图，拿到相对路径。
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        let relPath = try LocalImageStore.shared.saveImage(image)
        XCTAssertNotNil(LocalImageStore.readImageData(path: relPath))

        LocalImageStore.deleteImage(path: relPath)

        XCTAssertNil(LocalImageStore.readImageData(path: relPath),
                     "delete 应按 Documents 相对路径解析并真正删除文件")
    }

    func testDeleteImage_mockPathIsNoop() {
        // 不应崩溃，不应误删任何东西。
        LocalImageStore.deleteImage(path: "mock://placeholder")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/LocalImageStoreDeleteTests`
Expected: FAIL —— `deleteImage` 未定义。

- [ ] **Step 3: 实现 deleteImage**

在 `Notiee/Services/LocalImageStore.swift` 的 `readImageData` 方法之后插入：

```swift
    /// 删除由 saveImage 写入的图片（相对 Documents 解析，与 readImageData 口径一致）。
    nonisolated static func deleteImage(path: String) {
        guard !path.hasPrefix("mock://") else { return }
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsDirectory.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: fileURL)
    }
```

- [ ] **Step 4: 把 RecordManager 的删除切到新 API**

在 `Notiee/Services/Managers/RecordManager.swift`，`permanentlyDelete(id:)` 里：

```swift
        for path in record.localImagePaths {
            try? FileManager.default.removeItem(atPath: path)
        }
```
改为：
```swift
        for path in record.localImagePaths {
            LocalImageStore.deleteImage(path: path)
        }
```

`permanentlyDeleteMultiple(ids:)` 里同样的两行：
```swift
                for path in record.localImagePaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
```
改为：
```swift
                for path in record.localImagePaths {
                    LocalImageStore.deleteImage(path: path)
                }
```

- [ ] **Step 5: 跑测试确认通过**

Run: 同 Step 2。
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add Notiee/Services/LocalImageStore.swift Notiee/Services/Managers/RecordManager.swift NotieeTests/LocalImageStoreDeleteTests.swift
git commit -m "fix(images): delete captured images via Documents-relative path

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: 删除拍记时清理向量索引（#10）

**问题：** `EmbeddingIndex.remove(id:)` 全仓零调用方；`permanentlyDelete` 不通知索引，删除后向量永久驻留（存储膨胀 + 隐私残留）。用解耦回调而非硬编码依赖，便于测试。

**Files:**
- Modify: `Notiee/Services/Managers/RecordManager.swift`
- Modify: `Notiee/Services/NotieeStore.swift`（`live` 工厂里接线）
- Test: `NotieeTests/RecordDeletionHookTests.swift`

- [ ] **Step 1: 写失败测试**

Create `NotieeTests/RecordDeletionHookTests.swift`:

```swift
import XCTest
@testable import Notiee

@MainActor
final class RecordDeletionHookTests: XCTestCase {
    private func makeManager(_ records: [NoteRecord]) -> RecordManager {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID()).json")
        return RecordManager(
            records: records,
            todos: [],
            recordStore: JSONNoteRecordStore(fileURL: url),
            todoStore: JSONNoteTodoStore(fileURL: url.appendingPathExtension("todos"))
        )
    }

    func testPermanentlyDelete_firesHookWithDeletedID() {
        let rec = NoteRecord(localImagePaths: [], title: "t", processingState: .completed)
        let mgr = makeManager([rec])
        var captured: [UUID] = []
        mgr.onRecordsDeleted = { captured.append(contentsOf: $0) }

        mgr.permanentlyDelete(id: rec.id)

        XCTAssertEqual(captured, [rec.id])
    }

    func testPermanentlyDeleteMultiple_firesHookWithAllIDs() {
        let a = NoteRecord(localImagePaths: [], title: "a", processingState: .completed)
        let b = NoteRecord(localImagePaths: [], title: "b", processingState: .completed)
        let mgr = makeManager([a, b])
        var captured: Set<UUID> = []
        mgr.onRecordsDeleted = { captured.formUnion($0) }

        mgr.permanentlyDeleteMultiple(ids: [a.id, b.id])

        XCTAssertEqual(captured, [a.id, b.id])
    }
}
```

> 若 `NoteRecord(localImagePaths:title:processingState:)` 便捷 init 参数名与实际不符，用 `NoteCreateTool` 里同款的 `NoteRecord(eventID:folderID:localImagePaths:title:summary:detailedContent:processingState:source:)` 初始化替代——关键只是造一条带已知 id 的记录。

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/RecordDeletionHookTests`
Expected: FAIL —— `onRecordsDeleted` 未定义。

- [ ] **Step 3: 给 RecordManager 加回调并触发**

在 `Notiee/Services/Managers/RecordManager.swift` 顶部 `@Published var lastPersistenceError: String?` 之后加：

```swift
    /// 记录被永久删除后回调（携带被删 id），供索引/附件等旁路清理。
    var onRecordsDeleted: (([UUID]) -> Void)?
```

`permanentlyDelete(id:)` 末尾（`persistTodos()` 之后）加：
```swift
        onRecordsDeleted?([id])
```

`permanentlyDeleteMultiple(ids:)` 改为收集被删 id 后回调：
```swift
    func permanentlyDeleteMultiple(ids: Set<UUID>) {
        var deletedIDs: [UUID] = []
        records.removeAll { record in
            if ids.contains(record.id) {
                if !record.isDeleted {
                    accumulateDeletedTokens(record.tokenUsage)
                }
                for path in record.localImagePaths {
                    LocalImageStore.deleteImage(path: path)
                }
                todos.removeAll { $0.recordID == record.id }
                deletedIDs.append(record.id)
                return true
            }
            return false
        }
        persistRecords()
        persistTodos()
        onRecordsDeleted?(deletedIDs)
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。
Expected: PASS。

- [ ] **Step 5: 在 NotieeStore.live 接线到两个索引**

在 `Notiee/Services/NotieeStore.swift` 的 `live(...)` 里，`RecordManager(...)` 构造完成之后（`recordMgr` 已存在处）加：

```swift
        recordMgr.onRecordsDeleted = { ids in
            for id in ids {
                EmbeddingIndex.live.remove(id: id)
                EmbeddingIndex.relatedNotes.remove(id: id)
            }
        }
```

> `EmbeddingIndex.live` / `.relatedNotes` 均为 `@MainActor` 单例；`RecordManager` 也是 `@MainActor`，回调在主线程执行，安全。

- [ ] **Step 6: 编译确认**

Run: `xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 7: 提交**

```bash
git add Notiee/Services/Managers/RecordManager.swift Notiee/Services/NotieeStore.swift NotieeTests/RecordDeletionHookTests.swift
git commit -m "fix(index): purge embedding vectors when records are permanently deleted

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Hybrid 向量按真实来源打标签（#9）

**问题：** `HybridEmbeddingService.modelIdentifier` 独立于 `embed()` 实际返回值计算：云端瞬时失败会 fallback 本地 512 维向量，却仍被打上 `cloud-...` 标签写入索引，下次缓存命中拿 512 维与 1536 维 query 比 cosine → 静默 0 分。让计算向量时同时返回“真正产出它的模型”。

**Files:**
- Modify: `Notiee/Services/Semantic/EmbeddingService.swift`
- Modify: `Notiee/Services/Semantic/HybridEmbeddingService.swift`
- Modify: `Notiee/Services/Semantic/SemanticSearchEngine.swift:64-65`
- Test: `NotieeTests/HybridEmbeddingServiceTests.swift`（追加）

- [ ] **Step 1: 写失败测试（追加到现有文件）**

在 `NotieeTests/HybridEmbeddingServiceTests.swift` 追加（若文件里还没有 stub，先加这两个 stub）：

```swift
    // MARK: - embedTagged 来源标签

    private struct StubEmbed: EmbeddingService {
        let modelIdentifier: String
        let result: [Float]?          // nil 表示抛错（模拟云端故障）
        func embed(_ text: String) async throws -> [Float] {
            guard let r = result else { throw EmbeddingError.cannotEmbed }
            return r
        }
    }

    func testEmbedTagged_cloudSuccess_tagsCloudModel() async throws {
        let hybrid = HybridEmbeddingService(
            local: StubEmbed(modelIdentifier: "local", result: [0, 0]),
            cloud: StubEmbed(modelIdentifier: "cloud-x", result: [1, 2, 3]),
            preferCloud: { true })
        let out = try await hybrid.embedTagged("hi")
        XCTAssertEqual(out.model, "cloud-x")
        XCTAssertEqual(out.vector, [1, 2, 3])
    }

    func testEmbedTagged_cloudFails_tagsLocalModel() async throws {
        let hybrid = HybridEmbeddingService(
            local: StubEmbed(modelIdentifier: "local", result: [0, 0]),
            cloud: StubEmbed(modelIdentifier: "cloud-x", result: nil),   // 云端故障
            preferCloud: { true })
        let out = try await hybrid.embedTagged("hi")
        XCTAssertEqual(out.model, "local", "fallback 到本地时必须打本地标签，不能仍写 cloud-*")
        XCTAssertEqual(out.vector, [0, 0])
    }
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/HybridEmbeddingServiceTests`
Expected: FAIL —— `EmbeddingResult` / `embedTagged` 未定义。

- [ ] **Step 3: 在协议里加 EmbeddingResult 与默认 embedTagged**

在 `Notiee/Services/Semantic/EmbeddingService.swift`，`protocol EmbeddingService` 之后加：

```swift
/// 一次向量计算的结果 + 真正产出它的模型标识（用于给索引条目打准确标签）。
struct EmbeddingResult: Sendable {
    let vector: [Float]
    let model: String
}

extension EmbeddingService {
    /// 默认实现：单一后端时模型标识恒定。Hybrid 需 override 以反映“实际用了哪个后端”。
    func embedTagged(_ text: String) async throws -> EmbeddingResult {
        EmbeddingResult(vector: try await embed(text), model: modelIdentifier)
    }
}
```

- [ ] **Step 4: Hybrid override，返回真实来源**

在 `Notiee/Services/Semantic/HybridEmbeddingService.swift`，`embed(_:)` 之后加：

```swift
    func embedTagged(_ text: String) async throws -> EmbeddingResult {
        if preferCloud(), let cloud {
            if let v = try? await cloud.embed(text) {
                return EmbeddingResult(vector: v, model: cloud.modelIdentifier)
            }
        }
        let v = try await local.embed(text)
        return EmbeddingResult(vector: v, model: local.modelIdentifier)
    }
```

- [ ] **Step 5: 让写索引处用 embedTagged**

在 `Notiee/Services/Semantic/SemanticSearchEngine.swift` 的 `ensureVector` 里：

```swift
        guard let vector = try? await embeddingService.embed(text) else { return nil }
        index.set(EmbeddingEntry(vector: vector, model: embeddingService.modelIdentifier, contentHash: hash), for: record.id)
        return vector
```

替换为：

```swift
        guard let result = try? await embeddingService.embedTagged(text) else { return nil }
        index.set(EmbeddingEntry(vector: result.vector, model: result.model, contentHash: hash), for: record.id)
        return result.vector
```

> 读侧的 `existing.model == embeddingService.modelIdentifier` 保持不变：当云端偏好时，本地标签的旧条目会被判为“过期”→ 重算 → 云端恢复后自愈，正是期望行为。

- [ ] **Step 6: 跑测试确认通过**

Run: 同 Step 2。
Expected: PASS（含文件里原有用例）。

- [ ] **Step 7: 提交**

```bash
git add Notiee/Services/Semantic/EmbeddingService.swift Notiee/Services/Semantic/HybridEmbeddingService.swift Notiee/Services/Semantic/SemanticSearchEngine.swift NotieeTests/HybridEmbeddingServiceTests.swift
git commit -m "fix(embeddings): tag index entries with the backend that actually produced the vector

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: 自定义模型 API Key 存 Keychain（#2）

**问题：** `saveCustomModels` 把含 `apiKey` 的模型数组明文编码进 UserDefaults plist（会进 iCloud 备份 / 越狱可读）。内置模型已走 Keychain，自定义模型应一致。逐条把 key 写 Keychain、blob 里抹空；load 时回填；并对存量明文做一次迁移、对删除的模型清理 Keychain。

**Files:**
- Modify: `Notiee/Services/UserDefaultsAppSettingsStore.swift:122-134`
- Test: `NotieeTests/CustomModelKeychainTests.swift`

- [ ] **Step 1: 写失败测试**

Create `NotieeTests/CustomModelKeychainTests.swift`:

```swift
import XCTest
@testable import Notiee

final class CustomModelKeychainTests: XCTestCase {
    /// 内存版 SecretPersisting，避免测试污染真机 Keychain。
    private final class InMemorySecrets: SecretPersisting {
        var storage: [String: String] = [:]
        func string(forKey key: String) -> String? { storage[key] }
        func setString(_ value: String, forKey key: String) throws { storage[key] = value }
        func removeString(forKey key: String) throws { storage[key] = nil }
    }

    private func makeStore() -> (UserDefaultsAppSettingsStore, UserDefaults, InMemorySecrets) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let secrets = InMemorySecrets()
        let store = UserDefaultsAppSettingsStore(userDefaults: defaults, secretStore: secrets)
        return (store, defaults, secrets)
    }

    func testSave_writesKeyToKeychain_andBlanksBlob() throws {
        let (store, defaults, secrets) = makeStore()
        let model = CustomAIModel(name: "m", kind: .text, endpoint: "https://x",
                                  protocolType: .openai, modelIdentifier: "gpt", apiKey: "sk-SECRET")
        store.saveCustomModels([model])

        // Keychain 里有明文 key。
        XCTAssertTrue(secrets.storage.values.contains("sk-SECRET"))
        // UserDefaults blob 里不含明文 key。
        let raw = defaults.data(forKey: "notiee.customModels")!
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("sk-SECRET"))
    }

    func testLoad_restoresKeyFromKeychain() throws {
        let (store, _, _) = makeStore()
        let model = CustomAIModel(name: "m", kind: .text, endpoint: "https://x",
                                  protocolType: .openai, modelIdentifier: "gpt", apiKey: "sk-SECRET")
        store.saveCustomModels([model])

        let loaded = store.loadCustomModels()
        XCTAssertEqual(loaded.first?.apiKey, "sk-SECRET")
    }

    func testLoad_migratesLegacyPlaintextBlob() throws {
        let (store, defaults, secrets) = makeStore()
        // 模拟旧版：apiKey 明文直接在 blob 里，Keychain 为空。
        let legacy = CustomAIModel(name: "m", kind: .text, endpoint: "https://x",
                                   protocolType: .openai, modelIdentifier: "gpt", apiKey: "sk-LEGACY")
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "notiee.customModels")

        let loaded = store.loadCustomModels()

        XCTAssertEqual(loaded.first?.apiKey, "sk-LEGACY")
        XCTAssertTrue(secrets.storage.values.contains("sk-LEGACY"), "load 应把存量明文迁移进 Keychain")
        let raw = defaults.data(forKey: "notiee.customModels")!
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("sk-LEGACY"), "迁移后 blob 应抹空明文")
    }

    func testSave_removesKeychainEntryForDeletedModel() throws {
        let (store, _, secrets) = makeStore()
        let a = CustomAIModel(name: "a", kind: .text, endpoint: "https://x",
                              protocolType: .openai, modelIdentifier: "gpt", apiKey: "sk-A")
        store.saveCustomModels([a])
        XCTAssertTrue(secrets.storage.values.contains("sk-A"))

        store.saveCustomModels([])   // 删除 a
        XCTAssertFalse(secrets.storage.values.contains("sk-A"), "删除模型应清理其 Keychain 条目")
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/CustomModelKeychainTests`
Expected: FAIL —— 现实现明文进 blob，`testSave_...blanksBlob` / 迁移用例失败。

- [ ] **Step 3: 重写 load/save**

在 `Notiee/Services/UserDefaultsAppSettingsStore.swift` 把现有 `loadCustomModels` / `saveCustomModels` 整体替换为：

```swift
    private func customModelKeychainKey(_ id: UUID) -> String {
        "customModel.apiKey.\(id.uuidString)"
    }

    func loadCustomModels() -> [CustomAIModel] {
        guard let data = userDefaults.data(forKey: UDK.customModels),
              var models = try? JSONDecoder().decode([CustomAIModel].self, from: data) else {
            return []
        }
        var needsMigration = false
        for i in models.indices {
            if let stored = secretStore.string(forKey: customModelKeychainKey(models[i].id)) {
                models[i].apiKey = stored
            } else if !models[i].apiKey.isEmpty {
                // 旧版：明文 key 仍在 blob 里 → 保留值，触发一次迁移落 Keychain。
                needsMigration = true
            }
        }
        if needsMigration {
            saveCustomModels(models)
        }
        return models
    }

    func saveCustomModels(_ models: [CustomAIModel]) {
        // 清理已删除模型的 Keychain 条目。
        if let oldData = userDefaults.data(forKey: UDK.customModels),
           let oldModels = try? JSONDecoder().decode([CustomAIModel].self, from: oldData) {
            let newIDs = Set(models.map { $0.id })
            for old in oldModels where !newIDs.contains(old.id) {
                try? secretStore.removeString(forKey: customModelKeychainKey(old.id))
            }
        }
        // 每条 key 写 Keychain，并从 blob 抹空。
        var sanitized = models
        for i in sanitized.indices {
            let key = customModelKeychainKey(sanitized[i].id)
            if sanitized[i].apiKey.isEmpty {
                try? secretStore.removeString(forKey: key)
            } else {
                try? secretStore.setString(sanitized[i].apiKey, forKey: key)
            }
            sanitized[i].apiKey = ""
        }
        if let data = try? JSONEncoder().encode(sanitized) {
            userDefaults.set(data, forKey: UDK.customModels)
        }
    }
```

> 消费方（`CustomModelsListView`、AI 请求构造）继续从 `loadCustomModels()` 拿到已回填 `apiKey` 的模型，无需改动。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。
Expected: PASS（4 个用例）。

- [ ] **Step 5: 提交**

```bash
git add Notiee/Services/UserDefaultsAppSettingsStore.swift NotieeTests/CustomModelKeychainTests.swift
git commit -m "fix(security): store custom-model API keys in Keychain, migrate legacy plaintext

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: TMN 导入路径穿越校验（#3）

**问题：** `appendingPathComponent(manifest.content.main)` / `appendingPathComponent(ref.path)` 不归并 `..`，`manifest.content.main = "../../../Library/Preferences/....plist"` 可读沙盒内任意文件。所有从归档清单解析出的相对路径都必须限制在解压临时目录内。

**Files:**
- Modify: `Notiee/Services/TMNImportService.swift`
- Test: `NotieeTests/TMNPathSafetyTests.swift`

- [ ] **Step 1: 写失败测试**

Create `NotieeTests/TMNPathSafetyTests.swift`:

```swift
import XCTest
@testable import Notiee

@MainActor
final class TMNPathSafetyTests: XCTestCase {
    func testSecureResolve_rejectsTraversal() {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tmn-\(UUID())")
        XCTAssertThrowsError(try TMNImportService.secureResolve(base: base, relative: "../../etc/passwd"))
        XCTAssertThrowsError(try TMNImportService.secureResolve(base: base, relative: "../secret.plist"))
    }

    func testSecureResolve_allowsInsidePaths() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tmn-\(UUID())")
        let url = try TMNImportService.secureResolve(base: base, relative: "images/a.jpg")
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(base.standardizedFileURL.path + "/"))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/TMNPathSafetyTests`
Expected: FAIL —— `secureResolve` 未定义。

- [ ] **Step 3: 实现 secureResolve 并接入**

在 `Notiee/Services/TMNImportService.swift`，`final class TMNImportService {` 之后加（internal，供 `@testable` 访问）：

```swift
    /// 把归档清单里的相对路径限制在解压根目录内，阻断 `..` 路径穿越。
    static func secureResolve(base: URL, relative: String) throws -> URL {
        let resolved = base.appendingPathComponent(relative).standardizedFileURL
        let root = base.standardizedFileURL.path
        guard resolved.path == root || resolved.path.hasPrefix(root + "/") else {
            throw NSError(domain: "TMNImport", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "归档内非法路径：\(relative)"])
        }
        return resolved
    }
```

把：
```swift
        let contentURL = tempDir.appendingPathComponent(manifest.content.main)
```
改为：
```swift
        let contentURL = try Self.secureResolve(base: tempDir, relative: manifest.content.main)
```

把附件循环里的：
```swift
                let sourcePath = tempDir.appendingPathComponent(ref.path)
                if FileManager.default.fileExists(atPath: sourcePath.path) {
```
改为：
```swift
                guard let sourcePath = try? Self.secureResolve(base: tempDir, relative: ref.path) else { continue }
                if FileManager.default.fileExists(atPath: sourcePath.path) {
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2。
Expected: PASS。

- [ ] **Step 5: 编译确认导入流程仍通过**

Run: `xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED。

- [ ] **Step 6: 提交**

```bash
git add Notiee/Services/TMNImportService.swift NotieeTests/TMNPathSafetyTests.swift
git commit -m "fix(security): reject path traversal in TMN archive imports

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: 修复 Agent 撤销链路（#7）

**问题：**
1. `AgentExecutor.undoAction` 的快照分支把解码结果赋给 `_` 后丢弃（从不写回），且 `writeSnapshot` 全仓零调用方——该分支是死代码。
2. 创建类工具（note/todo/schedule_create）的撤销 `toolName` 指向 `note_delete`/`todo_delete`/`schedule_delete`，但这三个工具从未注册 → 撤销必抛 `toolNotFound`。

**修法：** 新增三个 delete 工具，标记为**模型不可见**（只供撤销用，不暴露给 LLM，避免给模型开删除能力）；注册它们；移除死的快照分支。

**Files:**
- Modify: `Notiee/Features/Spark/Agent/AgentToolProtocol.swift`
- Modify: `Notiee/Features/Spark/Agent/AgentToolRegistry.swift:18-20`
- Create: `Notiee/Features/Spark/Agent/Tools/NoteDeleteTool.swift`
- Create: `Notiee/Features/Spark/Agent/Tools/TodoDeleteTool.swift`
- Create: `Notiee/Features/Spark/Agent/Tools/ScheduleDeleteTool.swift`
- Modify: `Notiee/Features/Spark/SparkViewModel.swift:520-539`
- Modify: `Notiee/Features/Spark/Agent/AgentExecutor.swift:168-179`
- Test: `NotieeTests/AgentUndoDeleteToolsTests.swift`

- [ ] **Step 1: 写失败测试**

Create `NotieeTests/AgentUndoDeleteToolsTests.swift`:

```swift
import XCTest
@testable import Notiee

@MainActor
final class AgentUndoDeleteToolsTests: XCTestCase {
    private func makeManager(_ records: [NoteRecord], _ todos: [NoteTodo]) -> RecordManager {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID()).json")
        return RecordManager(
            records: records, todos: todos,
            recordStore: JSONNoteRecordStore(fileURL: url),
            todoStore: JSONNoteTodoStore(fileURL: url.appendingPathExtension("todos")))
    }

    func testNoteDeleteTool_removesRecord() async throws {
        let rec = NoteRecord(localImagePaths: [], title: "t", processingState: .completed)
        let mgr = makeManager([rec], [])
        let tool = NoteDeleteTool(recordManager: mgr)

        let result = try await tool.execute(parameters: ["record_id": rec.id.uuidString])

        XCTAssertTrue(result.success)
        XCTAssertFalse(mgr.records.contains { $0.id == rec.id })
    }

    func testTodoDeleteTool_removesTodo() async throws {
        let todo = NoteTodo(recordID: nil, content: "x")
        let mgr = makeManager([], [todo])
        let tool = TodoDeleteTool(recordManager: mgr)

        let result = try await tool.execute(parameters: ["todo_id": todo.id.uuidString])

        XCTAssertTrue(result.success)
        XCTAssertFalse(mgr.todos.contains { $0.id == todo.id })
    }

    func testDeleteTools_areHiddenFromModel() {
        let rec = makeManager([], [])
        let registry = AgentToolRegistry(tools: [
            NoteDeleteTool(recordManager: rec),
            TodoDeleteTool(recordManager: rec)
        ])
        // 注册后可被撤销按名取到……
        XCTAssertNotNil(registry.get("note_delete"))
        // ……但不出现在给模型的工具清单里。
        let modelNames = registry.allTools(for: .full).map { $0.name }
        XCTAssertFalse(modelNames.contains("note_delete"))
        XCTAssertFalse(modelNames.contains("todo_delete"))
    }
}
```

> `ScheduleDeleteTool` 需 `CalendarManager`，其构造依赖较多，故本测试只覆盖 note/todo + 可见性；schedule 走同一模式，编译期保证一致。

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/AgentUndoDeleteToolsTests`
Expected: FAIL —— 三个 delete 工具与 `visibleToModel` 未定义。

- [ ] **Step 3: 给协议加 visibleToModel（默认可见）**

在 `Notiee/Features/Spark/Agent/AgentToolProtocol.swift` 的 `protocol AgentTool` 里加一个带默认值的属性。先在协议体加：

```swift
    var visibleToModel: Bool { get }
```

再在文件内 `protocol AgentTool { ... }` 之后加默认实现：

```swift
extension AgentTool {
    /// 默认对模型可见。撤销专用工具 override 为 false。
    var visibleToModel: Bool { true }
}
```

- [ ] **Step 4: 让 allTools 过滤 visibleToModel**

在 `Notiee/Features/Spark/Agent/AgentToolRegistry.swift`：

```swift
    func allTools(for trustLevel: AgentTrustLevel) -> [any AgentTool] {
        tools.values.filter { $0.permission.isAllowed(by: trustLevel) }
    }
```
改为：
```swift
    func allTools(for trustLevel: AgentTrustLevel) -> [any AgentTool] {
        tools.values.filter { $0.visibleToModel && $0.permission.isAllowed(by: trustLevel) }
    }
```

> `get(_:)` 不过滤，撤销仍能按名取到隐藏工具。

- [ ] **Step 5: 新建三个 delete 工具**

Create `Notiee/Features/Spark/Agent/Tools/NoteDeleteTool.swift`:

```swift
import Foundation

/// 撤销专用：删除拍记。不对模型暴露（visibleToModel = false）。
@MainActor
final class NoteDeleteTool: AgentTool {
    let name = "note_delete"
    let description = "删除指定拍记（撤销专用，模型不可直接调用）"
    let permission: AgentToolPermission = .destructive
    var visibleToModel: Bool { false }

    let parametersSchema = AgentToolParametersSchema(
        properties: ["record_id": AgentToolProperty(type: "string", description: "要删除的拍记UUID", enumValues: nil, items: nil)],
        required: ["record_id"]
    )

    let recordManager: RecordManager
    init(recordManager: RecordManager) { self.recordManager = recordManager }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let idStr = parameters["record_id"] as? String, let id = UUID(uuidString: idStr) else {
            throw AgentToolError.missingParameter("record_id")
        }
        recordManager.permanentlyDelete(id: id)
        return AgentToolResult(success: true, message: "已删除拍记", data: nil, undoAction: nil)
    }
}
```

Create `Notiee/Features/Spark/Agent/Tools/TodoDeleteTool.swift`:

```swift
import Foundation

/// 撤销专用：删除待办。不对模型暴露。
@MainActor
final class TodoDeleteTool: AgentTool {
    let name = "todo_delete"
    let description = "删除指定待办（撤销专用，模型不可直接调用）"
    let permission: AgentToolPermission = .destructive
    var visibleToModel: Bool { false }

    let parametersSchema = AgentToolParametersSchema(
        properties: ["todo_id": AgentToolProperty(type: "string", description: "要删除的待办UUID", enumValues: nil, items: nil)],
        required: ["todo_id"]
    )

    let recordManager: RecordManager
    init(recordManager: RecordManager) { self.recordManager = recordManager }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let idStr = parameters["todo_id"] as? String, let id = UUID(uuidString: idStr) else {
            throw AgentToolError.missingParameter("todo_id")
        }
        recordManager.deleteTodo(id: id)
        return AgentToolResult(success: true, message: "已删除待办", data: nil, undoAction: nil)
    }
}
```

Create `Notiee/Features/Spark/Agent/Tools/ScheduleDeleteTool.swift`:

```swift
import Foundation

/// 撤销专用：删除日程。不对模型暴露。
@MainActor
final class ScheduleDeleteTool: AgentTool {
    let name = "schedule_delete"
    let description = "删除指定日程（撤销专用，模型不可直接调用）"
    let permission: AgentToolPermission = .destructive
    var visibleToModel: Bool { false }

    let parametersSchema = AgentToolParametersSchema(
        properties: ["event_id": AgentToolProperty(type: "string", description: "要删除的日程UUID", enumValues: nil, items: nil)],
        required: ["event_id"]
    )

    let calendarManager: CalendarManager
    init(calendarManager: CalendarManager) { self.calendarManager = calendarManager }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let idStr = parameters["event_id"] as? String, let id = UUID(uuidString: idStr) else {
            throw AgentToolError.missingParameter("event_id")
        }
        calendarManager.deleteEvent(id: id)
        return AgentToolResult(success: true, message: "已删除日程", data: nil, undoAction: nil)
    }
}
```

> `recordManager.permanentlyDelete(id:)`、`recordManager.deleteTodo(id:)`、`calendarManager.deleteEvent(id:)` 均已存在（已核实）。

- [ ] **Step 6: 跑工具测试确认通过**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/AgentUndoDeleteToolsTests`
Expected: PASS。

- [ ] **Step 7: 在 SparkViewModel 注册三个 delete 工具**

在 `Notiee/Features/Spark/SparkViewModel.swift` 构造工具数组处（`let registry = AgentToolRegistry(tools: tools)` 之前，`tools` 组装块内），把三个 delete 工具追加进去。定位现有 `NoteCreateTool(recordManager:...)` / `ScheduleCreateTool(calendarManager:...)` 的构造，在同一数组里加：

```swift
            NoteDeleteTool(recordManager: recordManager),
            TodoDeleteTool(recordManager: recordManager),
            ScheduleDeleteTool(calendarManager: calendarManager),
```

> 用与相邻 create 工具**同名**的 `recordManager` / `calendarManager` 局部量；若该作用域里管理器命名不同（如 `store.recordManager`），照抄相邻 create 工具的写法即可。

- [ ] **Step 8: 移除死的快照分支，简化 undoAction**

在 `Notiee/Features/Spark/Agent/AgentExecutor.swift` 把：

```swift
    func undoAction(_ undoAction: AgentUndoActionData) async throws {
        if let path = undoAction.snapshotPath {
            let snapshotData = try actionStore.readSnapshot(path: path)
            _ = try JSONDecoder().decode([NoteRecord].self, from: snapshotData)
            try actionStore.deleteSnapshot(path: path)
        } else {
            guard let tool = toolRegistry.get(undoAction.toolName) else {
                throw AgentActionStoreError.toolNotFound
            }
            _ = try await tool.execute(parameters: undoAction.undoParametersDict)
        }
    }
```

替换为：

```swift
    func undoAction(_ undoAction: AgentUndoActionData) async throws {
        // 目前撤销一律通过“反向工具”执行（note/todo/schedule_delete）。
        // 快照式恢复尚无生产者（writeSnapshot 无调用方），故不再走解码-丢弃的死分支；
        // 一旦出现快照路径，明确抛错而非静默无效。
        guard undoAction.snapshotPath == nil else {
            throw AgentActionStoreError.notUndoable
        }
        guard let tool = toolRegistry.get(undoAction.toolName) else {
            throw AgentActionStoreError.toolNotFound
        }
        _ = try await tool.execute(parameters: undoAction.undoParametersDict)
    }
```

- [ ] **Step 9: 全量编译 + 跑本 Task 测试**

Run:
```bash
xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'
xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/AgentUndoDeleteToolsTests
```
Expected: BUILD SUCCEEDED；测试 PASS。

- [ ] **Step 10: 提交**

```bash
git add Notiee/Features/Spark/Agent/AgentToolProtocol.swift \
        Notiee/Features/Spark/Agent/AgentToolRegistry.swift \
        Notiee/Features/Spark/Agent/Tools/NoteDeleteTool.swift \
        Notiee/Features/Spark/Agent/Tools/TodoDeleteTool.swift \
        Notiee/Features/Spark/Agent/Tools/ScheduleDeleteTool.swift \
        Notiee/Features/Spark/SparkViewModel.swift \
        Notiee/Features/Spark/Agent/AgentExecutor.swift \
        NotieeTests/AgentUndoDeleteToolsTests.swift
git commit -m "fix(agent): make create-action undo work via hidden delete tools; drop dead snapshot branch

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

> **注意（Xcode 工程文件）：** 新增的 `.swift` 文件需加入 `Notiee` / `NotieeTests` target。若用命令行 `xcodebuild` 且工程用文件系统同步组（synchronized groups），会自动纳入；否则需在 Xcode 里确认每个新文件的 Target Membership 勾选正确后再提交 `Notiee.xcodeproj/project.pbxproj`。

---

## 全量回归

- [ ] **跑完整测试套件确认无回归**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: 全部 PASS（含既有用例）。

---

## 本计划范围外（建议各自另立计划）

这些是审查报告里确认但改动更大/属架构级的项，不塞进本批 P0 修复：

- **#12 iCloud 同步重写**：LWW 语义、墓碑/软删同步、重复 ID、非原子上传——需要一套同步模型设计。
- **#5/#6 Prompt 注入体系**：对 records/memory/OCR/网页内容统一做注入防护 + 记忆写入校验——涉及 SparkAIService 提示词架构。
- **#8 Agent action 日志脱敏 + TTL**：`AgentActions.json` 无限增长且含笔记正文。
- **#4 WebFetch 残留 SSRF**：DNS rebinding + 盲 SSRF（现有 IP 字面量防护已较完善，仅需补 `URLSessionDelegate` 逐跳校验 + 解析后 IP 校验）。
- **#16 Agent 信任模型**：确认门、参数 schema 校验、destructive 分层。
- **#13/#26 取消语义**：`Task.detached` 不可取消、fire-and-forget 污染历史。
- P1/P2 其余项（#14 OCR 后台化、#19 通知前缀清理、#20/#21 网络/权限处理等）。

---

## Self-Review

- **Spec coverage：** 报告里点名的 8 条“根因清晰、可控”缺陷（#1、#2、#3、#7、#9、#10、#11 + #1 的两个面）均有对应 Task；更大架构项在“范围外”明确列出并说明理由。✅
- **Placeholder scan：** 每个改代码步骤都给了完整代码/命令与期望输出；无 “TODO/待补/类似上文” 之类占位。测试里对 `NoteRecord` 便捷 init 参数名的不确定性以“若不符则用完整 init”明确兜底，非占位。✅
- **Type consistency：** 全程统一使用 `onRecordsDeleted`、`EmbeddingResult`、`embedTagged`、`visibleToModel`、`secureResolve`、`customModelKeychainKey`、`loadOrQuarantine`；delete 工具名 `note_delete`/`todo_delete`/`schedule_delete` 与 create 工具产出的 `undoAction.toolName` 一致；调用的 `permanentlyDelete(id:)`/`deleteTodo(id:)`/`deleteEvent(id:)`/`fileURL`/`secretStore.setString/removeString` 均已在代码中核实存在。✅
