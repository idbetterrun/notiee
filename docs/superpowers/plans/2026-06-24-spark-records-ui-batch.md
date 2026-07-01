# Spark/Records UI Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Distinguish three kinds of `NoteRecord` (photo / Spark-generated / plain-text) and wire up the resulting UI changes — Spark records get a logo thumbnail, no detail image, and live in a real "Spark 生成" folder shown under the 日程文件夹 section; add a "+" plain-text record creator; move Today's all-todos entry onto the count badge; add search to Spark history; refresh the Spark privacy-consent copy.

**Architecture:** Introduce a `RecordSource` enum on `NoteRecord` (backward-compatible decoding via a custom `init(from:)` defaulting missing values to `.photo`). All downstream UI branches on `record.source`. The "Spark 生成" folder is a real `CustomFolder` resolved by name through a new `FolderTagManager.findOrCreateFolder(named:)` helper, excluded from the 自建文件夹 list and rendered as a pinned row in the 日程文件夹 section. No new image assets — the Spark thumbnail reuses the existing `sparkles` + blue→green gradient brand mark.

**Tech Stack:** Swift 5 / SwiftUI, XCTest, JSON-file persistence (`JSONNoteRecordStore`), Combine-mirrored `NotieeStore`.

**Out of scope:** Item ⑥ (GRDB + FTS5 migration) — decided to defer; no code in this plan.

---

## File Structure

| File | Responsibility | Change |
|------|----------------|--------|
| `Notiee/Models/NoteRecord.swift` | Record model + new `RecordSource` enum + backward-compatible decoding | Modify |
| `Notiee/Services/RecordMigrator.swift` | Doc/version note for the new field | Modify |
| `Notiee/Services/Managers/FolderTagManager.swift` | `findOrCreateFolder(named:)` + `sparkFolderName` constant | Modify |
| `Notiee/Services/NotieeStore.swift` | Expose `findOrCreateFolder` + `sparkFolder` convenience | Modify |
| `Notiee/Features/Spark/Agent/Tools/NoteCreateTool.swift` | Tag created record `.spark`, assign to "Spark 生成" folder | Modify |
| `Notiee/Features/Spark/SparkViewModel.swift` | Hold `folderTagManager`, pass to `NoteCreateTool` | Modify |
| `Notiee/Features/Spark/SparkView.swift` | Pass `store.folderTagManager` into the view model | Modify |
| `Notiee/Features/Records/RecordThumbnailView.swift` | Branch thumbnail by `source` | Modify |
| `Notiee/Features/Records/RecordDetailView.swift` | Hide image preview when `source != .photo` | Modify |
| `Notiee/Features/Records/RecordsView.swift` | "+" toolbar button; exclude/pin Spark folder; present new-text sheet | Modify |
| `Notiee/Features/Records/NewTextRecordSheet.swift` | Minimal title+body editor for plain-text records | Create |
| `Notiee/Features/Today/TodayView.swift` | Move all-todos entry onto count badge | Modify |
| `Notiee/Features/Spark/SparkHistoryView.swift` | `.searchable` over title + message text | Modify |
| `Notiee/Features/Spark/SparkPrivacySheet.swift` | Reword the four privacy items | Modify |
| `NotieeTests/RecordSourceDecodingTests.swift` | Backward-compat decode test | Create |
| `NotieeTests/FolderTagManagerTests.swift` | `findOrCreateFolder` tests | Modify |
| `NotieeTests/NoteCreateToolTests.swift` | Spark source + folder assignment test | Create |

---

## Task 1: Add `RecordSource` to `NoteRecord` (backward-compatible)

**Files:**
- Modify: `Notiee/Models/NoteRecord.swift`
- Modify: `Notiee/Services/RecordMigrator.swift:1-12`
- Test: `NotieeTests/RecordSourceDecodingTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `NotieeTests/RecordSourceDecodingTests.swift`:

```swift
import XCTest
@testable import Notiee

final class RecordSourceDecodingTests: XCTestCase {

    // Old persisted JSON has no `source` key → must decode as .photo
    func testLegacyRecordDecodesAsPhoto() throws {
        let legacyJSON = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "capturedAt": 730000000,
            "localImagePaths": ["a.jpg"],
            "title": "Legacy",
            "ocrText": "",
            "summary": "",
            "detailedContent": "",
            "processingState": "completed",
            "keyPoints": [],
            "definitions": [],
            "isFavorite": false,
            "isDeleted": false,
            "tokenUsage": 0,
            "aiRetryCount": 0
        }
        """.data(using: .utf8)!

        let record = try JSONDecoder().decode(NoteRecord.self, from: legacyJSON)
        XCTAssertEqual(record.source, .photo)
        XCTAssertEqual(record.title, "Legacy")
    }

    // New records round-trip their source
    func testSparkRecordRoundTrips() throws {
        let original = NoteRecord(localImagePaths: [], title: "S", source: .spark)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NoteRecord.self, from: data)
        XCTAssertEqual(decoded.source, .spark)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/RecordSourceDecodingTests`
Expected: FAIL — `NoteRecord` has no `source` member / initializer mismatch (compile error).

- [ ] **Step 3: Add the enum, property, initializer param, and custom decoder**

In `Notiee/Models/NoteRecord.swift`, add the enum above `struct NoteRecord`:

```swift
enum RecordSource: String, Codable, Sendable {
    case photo   // 拍照/相册导入的拍记
    case spark   // Spark 生成的记录
    case text    // 用户手动创建的纯文字记录
}
```

Add the stored property to `NoteRecord` (after `deviceName`):

```swift
    var source: RecordSource
```

Add the parameter to the memberwise `init` (place it last, before the body; default keeps every existing call site compiling):

```swift
        deviceName: String? = UIDevice.current.modelName,
        source: RecordSource = .photo
    ) {
        ...
        self.deviceName = deviceName
        self.source = source
    }
```

Add an explicit `CodingKeys` + custom `init(from:)` so legacy JSON (and any future missing field) decodes safely. Put this inside `struct NoteRecord`, after the memberwise init. `encode(to:)` stays compiler-synthesized:

```swift
    private enum CodingKeys: String, CodingKey {
        case id, eventID, folderID, capturedAt, localImagePaths, title
        case ocrText, summary, detailedContent, processingState
        case keyPoints, definitions, isFavorite, isDeleted, editedAt
        case modelsUsed, tokenUsage, aiRetryCount, deviceName, source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        eventID = try c.decodeIfPresent(UUID.self, forKey: .eventID)
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        localImagePaths = try c.decodeIfPresent([String].self, forKey: .localImagePaths) ?? []
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "待处理记录"
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        detailedContent = try c.decodeIfPresent(String.self, forKey: .detailedContent) ?? ""
        processingState = try c.decodeIfPresent(AIProcessingState.self, forKey: .processingState) ?? .pending
        keyPoints = try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        definitions = try c.decodeIfPresent([KeyDefinition].self, forKey: .definitions) ?? []
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        modelsUsed = try c.decodeIfPresent([String].self, forKey: .modelsUsed)
        tokenUsage = try c.decodeIfPresent(Int.self, forKey: .tokenUsage) ?? 0
        aiRetryCount = try c.decodeIfPresent(Int.self, forKey: .aiRetryCount) ?? 0
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName)
        source = try c.decodeIfPresent(RecordSource.self, forKey: .source) ?? .photo
    }
```

- [ ] **Step 4: Update the migrator doc comment**

In `Notiee/Services/RecordMigrator.swift`, update the header comment (no version bump needed — the custom decoder handles the missing key in-place):

```swift
/// Handles schema migrations for the records JSON file.
/// Current version: 1.
/// Note: `NoteRecord.source` (added later) is decoded with a safe default
/// (.photo) via NoteRecord.init(from:), so no envelope version bump is required.
```

- [ ] **Step 5: Run test to verify it passes**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/RecordSourceDecodingTests`
Expected: PASS (both tests).

- [ ] **Step 6: Commit**

```bash
git add Notiee/Models/NoteRecord.swift Notiee/Services/RecordMigrator.swift NotieeTests/RecordSourceDecodingTests.swift
git commit -m "feat(records): add RecordSource with backward-compatible decoding"
```

---

## Task 2: `findOrCreateFolder(named:)` on FolderTagManager

**Files:**
- Modify: `Notiee/Services/Managers/FolderTagManager.swift:47-56` (near `createImportedFolder`)
- Modify: `Notiee/Services/NotieeStore.swift:294-306` (Folder Mutations section)
- Test: `NotieeTests/FolderTagManagerTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `NotieeTests/FolderTagManagerTests.swift` (in the Folder tests region):

```swift
    func testFindOrCreateFolderCreatesWhenMissing() {
        let mgr = makeManager()
        let id = mgr.findOrCreateFolder(named: "Spark 生成")
        XCTAssertEqual(mgr.customFolders.count, 1)
        XCTAssertEqual(mgr.customFolders.first?.id, id)
        XCTAssertEqual(mgr.customFolders.first?.name, "Spark 生成")
    }

    func testFindOrCreateFolderReusesExisting() {
        let existing = CustomFolder(name: "Spark 生成")
        let mgr = makeManager(folders: [existing])
        let id = mgr.findOrCreateFolder(named: "Spark 生成")
        XCTAssertEqual(id, existing.id)
        XCTAssertEqual(mgr.customFolders.count, 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/FolderTagManagerTests`
Expected: FAIL — `findOrCreateFolder` not a member of `FolderTagManager`.

- [ ] **Step 3: Implement the helper + constant**

In `Notiee/Services/Managers/FolderTagManager.swift`, add a static constant near the top of the class and the method right after `createImportedFolder()`:

```swift
    static let sparkFolderName = "Spark 生成"

    @discardableResult
    func findOrCreateFolder(named name: String) -> UUID {
        if let existing = customFolders.first(where: { $0.name == name }) {
            return existing.id
        }
        let folder = CustomFolder(name: name)
        customFolders.append(folder)
        persistFolders()
        return folder.id
    }
```

- [ ] **Step 4: Expose through NotieeStore**

In `Notiee/Services/NotieeStore.swift`, in the `// MARK: - Folder Mutations` section, add:

```swift
    @discardableResult
    func findOrCreateFolder(named name: String) -> UUID {
        folderTagManager.findOrCreateFolder(named: name)
    }

    var sparkFolder: CustomFolder? {
        customFolders.first { $0.name == FolderTagManager.sparkFolderName }
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/FolderTagManagerTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Notiee/Services/Managers/FolderTagManager.swift Notiee/Services/NotieeStore.swift NotieeTests/FolderTagManagerTests.swift
git commit -m "feat(folders): add findOrCreateFolder(named:) helper"
```

---

## Task 3: NoteCreateTool tags `.spark` and files into "Spark 生成"

**Files:**
- Modify: `Notiee/Features/Spark/Agent/Tools/NoteCreateTool.swift`
- Modify: `Notiee/Features/Spark/SparkViewModel.swift:65,78-84,507,524`
- Modify: `Notiee/Features/Spark/SparkView.swift:25`
- Test: `NotieeTests/NoteCreateToolTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `NotieeTests/NoteCreateToolTests.swift`:

```swift
import XCTest
@testable import Notiee

@MainActor
final class NoteCreateToolTests: XCTestCase {

    private func makeRecordManager() -> RecordManager {
        RecordManager(
            records: [],
            todos: [],
            recordStore: JSONNoteRecordStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        )
    }

    private func makeFolderManager() -> FolderTagManager {
        FolderTagManager(
            customFolders: [],
            customTags: EventTag.systemTags,
            eventTagMapping: [:],
            folderStore: JSONCustomFolderStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")),
            tagStore: JSONEventTagStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        )
    }

    func testCreateMarksSparkSourceAndFilesIntoSparkFolder() async throws {
        let records = makeRecordManager()
        let folders = makeFolderManager()
        let tool = NoteCreateTool(recordManager: records, folderTagManager: folders)

        let result = try await tool.execute(parameters: ["title": "笔记A", "content": "正文"])

        XCTAssertTrue(result.success)
        let created = try XCTUnwrap(records.records.first)
        XCTAssertEqual(created.source, .spark)
        let sparkFolder = try XCTUnwrap(folders.customFolders.first { $0.name == "Spark 生成" })
        XCTAssertEqual(created.folderID, sparkFolder.id)
    }

    func testSecondCreateReusesSameFolder() async throws {
        let records = makeRecordManager()
        let folders = makeFolderManager()
        let tool = NoteCreateTool(recordManager: records, folderTagManager: folders)

        _ = try await tool.execute(parameters: ["title": "A"])
        _ = try await tool.execute(parameters: ["title": "B"])

        XCTAssertEqual(folders.customFolders.filter { $0.name == "Spark 生成" }.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/NoteCreateToolTests`
Expected: FAIL — `NoteCreateTool(recordManager:folderTagManager:)` initializer does not exist.

- [ ] **Step 3: Update NoteCreateTool**

Replace the stored property / init / `execute` body in `Notiee/Features/Spark/Agent/Tools/NoteCreateTool.swift`:

```swift
    let recordManager: RecordManager
    let folderTagManager: FolderTagManager

    init(recordManager: RecordManager, folderTagManager: FolderTagManager) {
        self.recordManager = recordManager
        self.folderTagManager = folderTagManager
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let title = parameters["title"] as? String else {
            throw AgentToolError.missingParameter("title")
        }
        let content = parameters["content"] as? String ?? ""
        let eventID = (parameters["event_id"] as? String).flatMap(UUID.init(uuidString:))
        let folderID = folderTagManager.findOrCreateFolder(named: FolderTagManager.sparkFolderName)

        let newRecord = NoteRecord(
            eventID: eventID,
            folderID: folderID,
            localImagePaths: [],
            title: title,
            summary: String(content.prefix(400)),
            detailedContent: content,
            processingState: .completed,
            source: .spark
        )
        recordManager.addRecord(newRecord)

        return AgentToolResult(
            success: true,
            message: "已创建拍记「\(title)」",
            data: ["record_id": newRecord.id.uuidString],
            undoAction: AgentUndoAction(
                toolName: "note_delete",
                description: "删除刚刚创建的拍记「\(title)」",
                undoParameters: ["record_id": newRecord.id.uuidString],
                snapshotPath: nil
            )
        )
    }
```

> Note: `processingState: .completed` so Spark records are not queued for AI re-processing or counted as 待处理.

- [ ] **Step 4: Thread folderTagManager through the view model**

In `Notiee/Features/Spark/SparkViewModel.swift`:

Add the stored property near `let recordManager: RecordManager?` (line ~65):

```swift
    let folderTagManager: FolderTagManager?
```

Add the init parameter (line ~78-84) and assignment:

```swift
        recordManager: RecordManager? = nil,
        folderTagManager: FolderTagManager? = nil,
        ...
        self.recordManager = recordManager
        self.folderTagManager = folderTagManager
```

In `makeAgentExecutor()` (line ~507) update the guard and the tool construction (line ~524):

```swift
        guard let recordManager, let calendarManager, let folderTagManager else { return nil }
        ...
            NoteCreateTool(recordManager: recordManager, folderTagManager: folderTagManager),
```

- [ ] **Step 5: Update the SparkView construction site**

In `Notiee/Features/Spark/SparkView.swift:25`:

```swift
        let vm = SparkViewModel(recordManager: store.recordManager, folderTagManager: store.folderTagManager, calendarManager: store.calendarManager)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/NoteCreateToolTests`
Expected: PASS (both tests).

- [ ] **Step 7: Commit**

```bash
git add Notiee/Features/Spark/Agent/Tools/NoteCreateTool.swift Notiee/Features/Spark/SparkViewModel.swift Notiee/Features/Spark/SparkView.swift NotieeTests/NoteCreateToolTests.swift
git commit -m "feat(spark): note_create tags .spark source and files into Spark 生成 folder"
```

---

## Task 4: Thumbnail + detail render by source

**Files:**
- Modify: `Notiee/Features/Records/RecordThumbnailView.swift:30-45`
- Modify: `Notiee/Features/Records/RecordDetailView.swift:28-32` (the `imagePreview` call site in the body)

- [ ] **Step 1: Branch the thumbnail by source**

In `Notiee/Features/Records/RecordThumbnailView.swift`, replace the inner `Group { ... }` (lines 30-45) so non-photo sources show a branded icon instead of attempting to load an image:

```swift
            Group {
                switch record.source {
                case .spark:
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay {
                            Image(systemName: "sparkles")
                                .font(.system(size: size * 0.42, weight: .light))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.361, green: 0.682, blue: 0.980),
                                            Color(red: 0.325, green: 0.980, blue: 0.671)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                case .text:
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(NotieeColors.themed(.blue).opacity(0.12))
                        .overlay {
                            Image(systemName: "doc.text")
                                .font(.title3)
                                .foregroundStyle(NotieeColors.themed(.blue))
                        }
                case .photo:
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(record.processingState.tint.opacity(0.12))
                            .overlay {
                                Image(systemName: record.processingState == .completed ? "doc.richtext" : "photo")
                                    .font(.title3)
                                    .foregroundStyle(record.processingState.tint)
                            }
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
```

> The multi-image stacked-card background (lines 18-28) stays as-is — it only triggers when `localImagePaths.count > 1`, which never happens for `.spark`/`.text`.

- [ ] **Step 2: Hide the detail image preview for non-photo records**

In `Notiee/Features/Records/RecordDetailView.swift`, find where `imagePreview` is placed in the scrolling body (around line 31, right after `header`) and gate it:

```swift
                header
                if viewModel.record.source == .photo {
                    imagePreview
                }
```

> Leave the `imagePreview` definition (lines 210-268) untouched — it is simply no longer invoked for `.spark`/`.text`. The "无预览图片" placeholder therefore disappears for those records.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification**

Launch the app (or `/run`). Create a Spark record via the agent; confirm: (a) its list thumbnail shows the sparkles gradient mark, (b) its detail page shows no image block, (c) an existing photo record is unchanged.

- [ ] **Step 5: Commit**

```bash
git add Notiee/Features/Records/RecordThumbnailView.swift Notiee/Features/Records/RecordDetailView.swift
git commit -m "feat(records): source-aware thumbnail and detail image suppression"
```

---

## Task 5: "Spark 生成" folder appears under 日程文件夹, not 自建文件夹

**Files:**
- Modify: `Notiee/Features/Records/RecordsView.swift:78-146`

- [ ] **Step 1: Exclude the Spark folder from the 自建文件夹 list**

In `Notiee/Features/Records/RecordsView.swift`, add a computed helper to `RecordsView` (near `displayedRecords`, ~line 240):

```swift
    private var userCustomFolders: [CustomFolder] {
        store.customFolders.filter { $0.name != FolderTagManager.sparkFolderName }
    }
```

Then change the 自建文件夹 section guard (line 78) and its `ForEach` (line 91):

```swift
                if !userCustomFolders.isEmpty {
```
```swift
                            ForEach(userCustomFolders) { folder in
```

- [ ] **Step 2: Pin the Spark folder row into the 日程文件夹 section**

Change the 日程文件夹 section guard (line 120) so the section also appears when the Spark folder exists:

```swift
                if !store.eventsWithRecords.isEmpty || store.sparkFolder != nil {
```

Inside `if isEventFolderExpanded {` (after line 132, before the `ForEach(store.eventsWithRecords)`), add the pinned Spark row:

```swift
                            if let sparkFolder = store.sparkFolder {
                                NavigationLink {
                                    GenericRecordListView(
                                        title: sparkFolder.name,
                                        systemImage: "sparkles",
                                        records: store.sortedRecords.filter { $0.folderID == sparkFolder.id },
                                        store: store
                                    )
                                } label: {
                                    FolderSummaryRow(
                                        title: sparkFolder.name,
                                        systemImage: "sparkles",
                                        count: store.records.filter { $0.folderID == sparkFolder.id && !$0.isDeleted }.count
                                    )
                                }
                            }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification**

After creating a Spark record: the "Spark 生成" folder shows under 日程文件夹 with a sparkles icon and correct count, does NOT appear under 自建文件夹, and tapping it lists only Spark records.

- [ ] **Step 5: Commit**

```bash
git add Notiee/Features/Records/RecordsView.swift
git commit -m "feat(records): show Spark 生成 folder under 日程文件夹 section"
```

---

## Task 6: "+" toolbar button → new plain-text record (beta)

**Files:**
- Create: `Notiee/Features/Records/NewTextRecordSheet.swift`
- Modify: `Notiee/Features/Records/RecordsView.swift:7-8,182-192`

- [ ] **Step 1: Create the editor sheet**

Create `Notiee/Features/Records/NewTextRecordSheet.swift`:

```swift
import SwiftUI

struct NewTextRecordSheet: View {
    @ObservedObject var store: NotieeStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var body: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 标题：大字号、加粗
                    TextField("标题", text: $title, axis: .vertical)
                        .font(.system(size: 28, weight: .bold))
                        .textInputAutocapitalization(.sentences)

                    Divider()

                    // 正文：常规正文字号
                    TextField("正文", text: $body, axis: .vertical)
                        .font(.body)
                        .frame(minHeight: 200, alignment: .topLeading)
                }
                .padding(20)
            }
            .navigationTitle("纯文字记录（beta）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = NoteRecord(
            localImagePaths: [],
            title: trimmedTitle.isEmpty ? "无标题" : trimmedTitle,
            summary: String(body.prefix(400)),
            detailedContent: body,
            processingState: .completed,
            source: .text
        )
        store.addRecord(record)
        dismiss()
    }
}
```

> `body` is also the name of SwiftUI's `View.body`; here it is a local `@State` on a struct whose view content is the computed `var body`. They don't collide (one is a stored property, one is a protocol requirement) but to avoid confusion the implementer may rename the state to `bodyText`. If renamed, update both `TextField("正文", text: $bodyText...)` and `detailedContent: bodyText`.

- [ ] **Step 2: Add state + "+" button + sheet presentation in RecordsView**

In `Notiee/Features/Records/RecordsView.swift`, add state near the other `@State` declarations (after line 8):

```swift
    @State private var showingNewTextRecord = false
```

Replace the single toolbar item (lines 182-192) with two buttons — `+` on the left of the folder button:

```swift
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showingNewTextRecord = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("新建纯文字记录")

                        Button {
                            newFolderName = ""
                            showingCreateFolderAlert = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityLabel("新建文件夹")
                    }
                }
            }
            .sheet(isPresented: $showingNewTextRecord) {
                NewTextRecordSheet(store: store)
            }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification**

Tap "+" in 记录 → enter a title and body → 保存. Confirm the new record appears in 全部记录 with the `doc.text` thumbnail, opens with a bold large title + normal body, shows no image block, and is NOT in 待处理.

- [ ] **Step 5: Commit**

```bash
git add Notiee/Features/Records/NewTextRecordSheet.swift Notiee/Features/Records/RecordsView.swift
git commit -m "feat(records): add plain-text record creator (beta)"
```

---

## Task 7: Move Today's all-todos entry onto the count badge

**Files:**
- Modify: `Notiee/Features/Today/TodayView.swift:256-275`

- [ ] **Step 1: Wrap the count badge in a NavigationLink and remove the trailing link**

In `Notiee/Features/Today/TodayView.swift`, replace the `HStack` header of `todoSection` (lines 256-275) with:

```swift
            HStack(spacing: 8) {
                Text("待办事项")
                    .font(.title3.weight(.bold))

                if let store = viewModel.store {
                    NavigationLink {
                        AllTodosView(store: store)
                    } label: {
                        Text("\(viewModel.pendingTodos.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(.blue, in: Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("\(viewModel.pendingTodos.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(.blue, in: Circle())
                }

                Spacer()
            }
```

> The badge's visual style (caption2 bold white on a 20×20 blue circle) is preserved exactly; only its tappability and the removal of the "全部待办 →" link change.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual verification**

On Today, the "全部待办 →" text is gone; tapping the blue count circle navigates to AllTodosView; the circle looks identical to before.

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Today/TodayView.swift
git commit -m "feat(today): move all-todos entry onto the pending-count badge"
```

---

## Task 8: Search in Spark history

**Files:**
- Modify: `Notiee/Features/Spark/SparkHistoryView.swift:23-31,43-69`

- [ ] **Step 1: Add search state and filtering**

In `Notiee/Features/Spark/SparkHistoryView.swift`, add a search-text state to `SparkHistoryView` (after line 29 `@State private var selectedIDs`):

```swift
    @State private var searchText = ""
```

Add a computed property that filters then regroups (place it inside `SparkHistoryView`, before `body`):

```swift
    private var visibleGroups: [DateGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.groups }
        return store.groups.compactMap { group in
            let matched = group.conversations.filter { conv in
                conv.title.lowercased().contains(q)
                || conv.messages.contains { $0.content.lowercased().contains(q) }
            }
            return matched.isEmpty ? nil : DateGroup(date: group.date, conversations: matched)
        }
    }
```

- [ ] **Step 2: Drive the List off `visibleGroups` and add `.searchable`**

Change the `ForEach(store.groups)` (line 47) to:

```swift
                        ForEach(visibleGroups) { group in
```

Change the empty-state guard (line 44) to also cover "no search results":

```swift
                        if visibleGroups.isEmpty {
                            emptyView
                        }
```

Add the modifier on the `List` (after `List(selection: $selectedIDs) { ... }` closes, alongside the other List modifiers — practically, attach it where `.environment(\.editMode...)` is, i.e. add a line before `.onAppear`):

```swift
            .searchable(text: $searchText, prompt: "搜索标题或对话内容")
```

> Confirmed: `ChatMessage.content: String` (`SparkModels.swift:24`) is the message text field. Use `$0.content`.

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Manual verification**

Open 历史对话, type a keyword present in a conversation title and one present only in message bodies; both should filter correctly, and the empty state shows when nothing matches.

- [ ] **Step 5: Commit**

```bash
git add Notiee/Features/Spark/SparkHistoryView.swift
git commit -m "feat(spark): searchable conversation history (title + message text)"
```

---

## Task 9: Reword the Spark privacy-consent copy

**Files:**
- Modify: `Notiee/Features/Spark/SparkPrivacySheet.swift:24,29-55`

- [ ] **Step 1: Refresh the wording (structure and consent flow unchanged)**

In `Notiee/Features/Spark/SparkPrivacySheet.swift`, update the title (line 24) and the four `privacyItem(...)` blocks (lines 29-55). Keep the same four icons/colors and the four privacy facts; only the copy is modernized:

```swift
            Text(String(localized: "Spark · 你的知识助手"))
                .font(.title2.weight(.bold))
```

```swift
                privacyItem(
                    icon: "lock.shield",
                    color: Color(red: 0.325, green: 0.980, blue: 0.671),
                    title: String(localized: "检索在本地"),
                    detail: String(localized: "拍记的检索与匹配默认在你的设备上完成，原文不会被打包上传。")
                )

                privacyItem(
                    icon: "arrow.triangle.branch",
                    color: Color(red: 0.361, green: 0.682, blue: 0.980),
                    title: String(localized: "只发必要内容"),
                    detail: String(localized: "生成回答时，仅把你的问题和检索命中的少量片段发送给所选 AI 模型。")
                )

                privacyItem(
                    icon: "hand.raised",
                    color: .orange,
                    title: String(localized: "不用于训练"),
                    detail: String(localized: "你的拍记内容不会被用于模型训练，也不会分享给第三方。")
                )

                privacyItem(
                    icon: "globe",
                    color: Color(red: 0.6, green: 0.4, blue: 0.9),
                    title: String(localized: "联网读取需授权"),
                    detail: String(localized: "仅在 Agent 模式下、且你提供链接时，Spark 才会访问对应网页，相关请求会发往该第三方站点。")
                )
```

> The "了解，开始使用" button and `onAgree` consent callback are intentionally left unchanged — this remains a consent gate, not just an intro.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual verification**

Reset the privacy flag (fresh install or clear `hasSeenPrivacyNotice`), open Spark, confirm the refreshed copy renders and the agree button still dismisses and persists consent.

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Spark/SparkPrivacySheet.swift
git commit -m "feat(spark): refresh privacy-consent sheet copy"
```

---

## Task 10: Full regression build + test

- [ ] **Step 1: Run the whole suite**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED, all tests pass (including `RecordSourceDecodingTests`, `FolderTagManagerTests`, `NoteCreateToolTests`, and the pre-existing `RecordManagerTests`, `SparkConversationRepositoryTests`, etc.).

- [ ] **Step 2: Fix any fallout, then final commit if needed**

If any pre-existing test broke (e.g. a fixture that hard-codes `NoteRecord` field order or an exhaustive equality), fix it minimally and commit:

```bash
git add -A
git commit -m "test: fix fallout from RecordSource addition"
```

---

## Self-Review Notes (author checklist, already applied)

- **Spec coverage:** ① Task 4 (detail+thumbnail) · ② Tasks 2,3,5 (real folder, .spark source, 日程文件夹 placement) · ③ Task 8 · ④ Task 6 · ⑤ Task 7 · ⑦ Task 9. Item ⑥ intentionally excluded (deferred).
- **Type consistency:** `RecordSource` (`.photo/.spark/.text`), `FolderTagManager.sparkFolderName`, `findOrCreateFolder(named:)`, `NotieeStore.sparkFolder`, and the `NoteCreateTool(recordManager:folderTagManager:)` initializer are used identically across all tasks.
- **Dependencies verified:** `ChatMessage.content: String`, `NoteRecord` synthesized `Codable` (replaced by custom `init(from:)`), `FolderTagManager` init signature, and the `RecordManager`/`FolderTagManager` test construction patterns all checked against source before writing.
```
