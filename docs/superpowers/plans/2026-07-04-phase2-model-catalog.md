# Phase 2: 模型目录 + 选模型界面 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Notiee 免费版用户能从一份「精选模型目录」里选文本/视觉模型（免费档可选免费模型、Pro 模型加锁），选择持久化并被后端 AI 调用消费。

**Architecture:** 新增一个纯数据的静态目录 `CuratedModelCatalog`（含档位）+ 一个 UserDefaults 持久化的 `CuratedModelSelection`（带「按当前档位夹取」逻辑，保证调用方永远拿到合法模型）+ 一个硬编码 `.free` 的 `CurrentEntitlement`（Phase 4 换成真 EntitlementStore）。新增 `ModelPickerView` 展示目录。把 Phase 0 里写死的 `freeTextModel/freeVisionModel/freeModel` 换成读 selection。`SettingsMainView` 用 `#if NOTIEE_PLUS` 分叉：免费版进 ModelPicker，Notiee+ 保持 BYOK 配置不变。

**Tech Stack:** Swift / SwiftUI / XCTest；Xcode 工程双 target（`Notiee` 免费版、`Notiee+` BYOK）靠 `NOTIEE_PLUS` 编译标志区分。

**隔离规则（全程遵守）：**
- 新文件 `CuratedModelCatalog.swift` / `ModelPickerView.swift` / 测试文件 **只勾 `Notiee` target**（Notiee+ 里不存在）。
- `SettingsMainView.swift` 是共享文件，只允许通过 `#if NOTIEE_PLUS` 分叉，**不写运行时 `if 免费版`**。
- 档位真值 Phase 4 才有；本 Phase 一律用 `CurrentEntitlement.tier`（硬编码 `.free`）。

---

## File Structure

| 文件 | 责任 | 动作 | Target |
|---|---|---|---|
| `Notiee/Models/CuratedModelCatalog.swift` | 静态模型目录 + 档位夹取选择 + 当前档位入口 | 🆕 新建 | 仅 Notiee |
| `Notiee/Features/Settings/ModelPickerView.swift` | 选模型界面（Pro 加锁 → 提示） | 🆕 新建 | 仅 Notiee |
| `NotieeTests/CuratedModelCatalogTests.swift` | 目录/夹取/未知容错的单测 | 🆕 新建 | 测试（跑 Notiee） |
| `Notiee/Utils/UserDefaultsKeys.swift` | 新增两个 selection 键 | ✏️ 改 | 共享 |
| `Notiee/Services/BackendAIProcessingService.swift` | 消费选择：`/ai/process` 的 vision/text 模型 | ✏️ 改 | 仅 Notiee |
| `Notiee/Features/Spark/BackendSparkAIService.swift` | 消费选择：`/ai/chat` 的 model | ✏️ 改 | 仅 Notiee |
| `Notiee/Features/Settings/SettingsMainView.swift` | 免费版展示 ModelPicker、藏 BYOK/自定义模型 | ✏️ 改（`#if`） | 共享 |

**范围说明 / 对原始 §4 清单的修正：**
- `SparkSettingsView.swift` **本 Phase 不改**。核查代码发现它只有「聊天风格 / 记忆 / Agent 设置」三个入口，没有模型选择 UI；免费版 Spark 的模型跟随统一的「文本模型」selection（见 Task 3），Spark 专属的档位收紧（锁 flash、无 Agent）属于 **Phase 2.5**，不在此。
- `AIConfigurationView` / `CustomModelsListView` / `AIModelConfiguration` / `AIProvider` 保持共享、不改，免费版只是不给入口。

---

## Testing 说明（每个「运行测试」步骤通用）

本机是 Command Line Tools，`xcodebuild` 可能报 `requires Xcode`。二选一：

- **命令行**（需完整 Xcode）：先 `sudo xcode-select -s /Applications/Xcode.app`，再跑：
  ```bash
  xcodebuild test -project Notiee.xcodeproj -scheme Notiee \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:NotieeTests/CuratedModelCatalogTests \
    -only-testing:NotieeTests/CuratedModelSelectionTests
  ```
  模拟器名用 `xcrun simctl list devices available | grep iPhone` 挑一个真实存在的替换。
- **Xcode GUI**：打开工程，`⌘U` 跑全部测试，或点测试类左侧的菱形只跑这两个类。

---

## Task 1: 模型目录 + 档位夹取选择（TDD）

**Files:**
- Create: `Notiee/Models/CuratedModelCatalog.swift`（只勾 Notiee target）
- Modify: `Notiee/Utils/UserDefaultsKeys.swift`
- Test: `NotieeTests/CuratedModelCatalogTests.swift`（只勾 Notiee 测试）

- [ ] **Step 1: 加 UserDefaults 键**

在 `Notiee/Utils/UserDefaultsKeys.swift` 的 `// MARK: - Backend (Notiee free version)` 段之后（`backendBaseURL` 那行下面）加：

```swift
    // MARK: - Curated model selection (Notiee free version)
    /// 免费版选中的文本 / 视觉模型 ID（对应后端 MODEL_CATALOG 的 key）。
    /// 未设置或对当前档位非法时，读取端会夹取回免费默认模型。
    static let selectedTextModel = "notiee.selectedTextModel"
    static let selectedVisionModel = "notiee.selectedVisionModel"
```

- [ ] **Step 2: 写失败的测试**

创建 `NotieeTests/CuratedModelCatalogTests.swift`：

```swift
import XCTest
@testable import Notiee

final class CuratedModelCatalogTests: XCTestCase {

    // MARK: - 目录数据

    func testCatalogPartitionsFiveTextAndThreeVision() {
        XCTAssertEqual(CuratedModelCatalog.models(kind: .text).count, 5)
        XCTAssertEqual(CuratedModelCatalog.models(kind: .vision).count, 3)
    }

    func testModelIDsMatchBackendCatalogVerbatim() {
        let textIDs = Set(CuratedModelCatalog.models(kind: .text).map(\.id))
        XCTAssertEqual(textIDs, [
            "deepseek-v4-flash", "deepseek-v4-pro",
            "MiniMax-M3", "MiniMax-M2.7-highspeed", "MiniMax-M2.7",
        ])
        let visionIDs = Set(CuratedModelCatalog.models(kind: .vision).map(\.id))
        XCTAssertEqual(visionIDs, [
            "doubao-seed-2-0-mini", "doubao-seed-2-0-lite", "doubao-seed-2-1-pro",
        ])
    }

    func testExactlyOneFreeModelPerKind() {
        XCTAssertEqual(
            CuratedModelCatalog.models(kind: .text).filter { $0.tier == .free }.map(\.id),
            ["deepseek-v4-flash"])
        XCTAssertEqual(
            CuratedModelCatalog.models(kind: .vision).filter { $0.tier == .free }.map(\.id),
            ["doubao-seed-2-0-mini"])
    }

    // MARK: - 查找容错

    func testModelLookupReturnsNilForUnknownID() {
        XCTAssertNil(CuratedModelCatalog.model(id: "gpt-9-ultra"))
    }

    func testModelLookupFindsKnownID() {
        XCTAssertEqual(CuratedModelCatalog.model(id: "MiniMax-M3")?.tier, .pro)
    }

    // MARK: - 档位放行

    func testFreeTierAllowsOnlyFreeModels() {
        let flash = CuratedModelCatalog.model(id: "deepseek-v4-flash")!
        let m3 = CuratedModelCatalog.model(id: "MiniMax-M3")!
        XCTAssertTrue(CuratedModelCatalog.isAllowed(flash, for: .free))
        XCTAssertFalse(CuratedModelCatalog.isAllowed(m3, for: .free))
    }

    func testProTierAllowsAllModels() {
        let m3 = CuratedModelCatalog.model(id: "MiniMax-M3")!
        XCTAssertTrue(CuratedModelCatalog.isAllowed(m3, for: .pro))
    }

    func testDefaultModelIsTheFreeModelPerKind() {
        XCTAssertEqual(CuratedModelCatalog.defaultModel(kind: .text, for: .free).id, "deepseek-v4-flash")
        XCTAssertEqual(CuratedModelCatalog.defaultModel(kind: .vision, for: .free).id, "doubao-seed-2-0-mini")
    }
}

final class CuratedModelSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "curated-selection-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUnsetSelectionFallsBackToFreeDefault() {
        let sel = CuratedModelSelection(defaults: defaults)
        XCTAssertEqual(sel.textModelID(for: .free), "deepseek-v4-flash")
        XCTAssertEqual(sel.visionModelID(for: .free), "doubao-seed-2-0-mini")
    }

    func testFreeTierClampsStoredProModelToDefault() {
        let sel = CuratedModelSelection(defaults: defaults)
        sel.setTextModel("MiniMax-M3")            // pro 模型
        XCTAssertEqual(sel.textModelID(for: .free), "deepseek-v4-flash")  // 被夹回
    }

    func testProTierHonorsStoredProModel() {
        let sel = CuratedModelSelection(defaults: defaults)
        sel.setTextModel("MiniMax-M3")
        XCTAssertEqual(sel.textModelID(for: .pro), "MiniMax-M3")
    }

    func testUnknownStoredModelFallsBackToDefault() {
        let sel = CuratedModelSelection(defaults: defaults)
        sel.setTextModel("does-not-exist")
        XCTAssertEqual(sel.textModelID(for: .pro), "deepseek-v4-flash")
    }

    func testWrongKindStoredModelFallsBackToDefault() {
        let sel = CuratedModelSelection(defaults: defaults)
        sel.setTextModel("doubao-seed-2-0-mini")  // 把视觉模型存进文本槽
        XCTAssertEqual(sel.textModelID(for: .pro), "deepseek-v4-flash")
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

在 Xcode 里 `⌘U`（或用上方 xcodebuild 命令）。
Expected: 编译失败 / FAIL —— `CuratedModelCatalog`、`CuratedModelSelection`、`ModelTier`、`CuratedModelKind` 未定义。

- [ ] **Step 4: 写最小实现**

创建 `Notiee/Models/CuratedModelCatalog.swift`（**新建后务必只勾 Notiee target，不要勾 Notiee+**）：

```swift
import Foundation

enum ModelTier: String, Sendable {
    case free
    case pro
}

enum CuratedModelKind: String, Sendable {
    case text
    case vision
}

struct CuratedModel: Identifiable, Equatable, Sendable {
    let id: String          // 后端 MODEL_CATALOG 的 key，原样透传（如 "MiniMax-M2.7" 带点）
    let displayName: String
    let kind: CuratedModelKind
    let tier: ModelTier
}

/// Notiee（免费版）的精选模型目录。客户端只把这些 ID 发给后端，key 在后端。
/// ID 必须与后端 `MODEL_CATALOG` 完全一致。
///
/// 目前这份内置列表即事实来源；未来可由后端下发覆盖（届时再加）。在此之前，
/// 读取端对未知 ID 一律夹取回免费默认模型，模型下线/换名不必发版。
/// 仅 Notiee（免费）target。
enum CuratedModelCatalog {
    static let all: [CuratedModel] = [
        // 文本（免费在前，其余按价格高→低）
        CuratedModel(id: "deepseek-v4-flash",      displayName: "DeepSeek v4-flash",      kind: .text,   tier: .free),
        CuratedModel(id: "MiniMax-M3",             displayName: "MiniMax M3",             kind: .text,   tier: .pro),
        CuratedModel(id: "MiniMax-M2.7-highspeed", displayName: "MiniMax M2.7-highspeed", kind: .text,   tier: .pro),
        CuratedModel(id: "MiniMax-M2.7",           displayName: "MiniMax M2.7",           kind: .text,   tier: .pro),
        CuratedModel(id: "deepseek-v4-pro",        displayName: "DeepSeek v4-pro",        kind: .text,   tier: .pro),
        // 视觉（仅豆包，免费在前）
        CuratedModel(id: "doubao-seed-2-0-mini",   displayName: "Doubao-Seed-2.0-mini",   kind: .vision, tier: .free),
        CuratedModel(id: "doubao-seed-2-0-lite",   displayName: "Doubao-Seed-2.0-lite",   kind: .vision, tier: .pro),
        CuratedModel(id: "doubao-seed-2-1-pro",    displayName: "Doubao-Seed-2.1-Pro",    kind: .vision, tier: .pro),
    ]

    static func models(kind: CuratedModelKind) -> [CuratedModel] {
        all.filter { $0.kind == kind }
    }

    static func model(id: String) -> CuratedModel? {
        all.first { $0.id == id }
    }

    static func isAllowed(_ model: CuratedModel, for tier: ModelTier) -> Bool {
        tier == .pro ? true : model.tier == .free
    }

    /// 每种类型的安全默认：那唯一一个免费模型。未选择或选择对当前档位非法时用它。
    static func defaultModel(kind: CuratedModelKind, for tier: ModelTier) -> CuratedModel {
        models(kind: kind).first { $0.tier == .free } ?? models(kind: kind)[0]
    }
}

/// 免费版的模型选择，持久化到 UserDefaults，并按当前档位夹取——
/// 保证调用方永远拿到「当前档位允许」的模型 ID。
struct CuratedModelSelection {
    let defaults: UserDefaults
    static let live = CuratedModelSelection(defaults: .standard)

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func textModelID(for tier: ModelTier) -> String {
        resolved(stored: defaults.string(forKey: UDK.selectedTextModel), kind: .text, tier: tier)
    }

    func visionModelID(for tier: ModelTier) -> String {
        resolved(stored: defaults.string(forKey: UDK.selectedVisionModel), kind: .vision, tier: tier)
    }

    func setTextModel(_ id: String) { defaults.set(id, forKey: UDK.selectedTextModel) }
    func setVisionModel(_ id: String) { defaults.set(id, forKey: UDK.selectedVisionModel) }

    private func resolved(stored: String?, kind: CuratedModelKind, tier: ModelTier) -> String {
        if let stored,
           let model = CuratedModelCatalog.model(id: stored),
           model.kind == kind,
           CuratedModelCatalog.isAllowed(model, for: tier) {
            return stored
        }
        return CuratedModelCatalog.defaultModel(kind: kind, for: tier).id
    }
}

/// 当前档位入口。Phase 4 前硬编码 `.free`；届时改这一处即可让全 App 切到
/// 真档位（后端 `/me/quota` 的 tier，经 EntitlementStore）。
enum CurrentEntitlement {
    static var tier: ModelTier { .free }
}
```

- [ ] **Step 5: 运行测试确认通过**

`⌘U`（或 xcodebuild）。
Expected: `CuratedModelCatalogTests` + `CuratedModelSelectionTests` 全 PASS。

- [ ] **Step 6: 提交**

```bash
git add Notiee/Models/CuratedModelCatalog.swift \
        Notiee/Utils/UserDefaultsKeys.swift \
        NotieeTests/CuratedModelCatalogTests.swift
git commit -m "feat(catalog): curated model catalog + tier-clamped selection for free version"
```

---

## Task 2: 选模型界面 ModelPickerView

**Files:**
- Create: `Notiee/Features/Settings/ModelPickerView.swift`（只勾 Notiee target）

> SwiftUI 视图不做单测，靠**编译 + 手动核对**验证。逻辑已在 Task 1 覆盖，本视图只是薄壳。

- [ ] **Step 1: 写视图**

创建 `Notiee/Features/Settings/ModelPickerView.swift`（**只勾 Notiee target**）：

```swift
import SwiftUI

/// 免费版选模型界面：列出精选目录，免费档模型可选，Pro 模型加锁并提示升级
/// （Phase 4 接付费墙）。仅 Notiee（免费）target。
struct ModelPickerView: View {
    private let selection = CuratedModelSelection.live
    private var tier: ModelTier { CurrentEntitlement.tier }

    @State private var selectedText = ""
    @State private var selectedVision = ""
    @State private var showProAlert = false

    var body: some View {
        Form {
            modelSection(title: "文本模型", kind: .text, current: selectedText) { selectedText = $0 }
            modelSection(title: "视觉模型", kind: .vision, current: selectedVision) { selectedVision = $0 }
        }
        .navigationTitle("模型选择")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedText = selection.textModelID(for: tier)
            selectedVision = selection.visionModelID(for: tier)
        }
        .alert("Pro 专属模型", isPresented: $showProAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("该模型为 Pro 会员专属，升级后即可使用。")
        }
    }

    @ViewBuilder
    private func modelSection(
        title: String,
        kind: CuratedModelKind,
        current: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Section(title) {
            ForEach(CuratedModelCatalog.models(kind: kind)) { model in
                let allowed = CuratedModelCatalog.isAllowed(model, for: tier)
                Button {
                    if allowed {
                        store(kind: kind, id: model.id)
                        onSelect(model.id)
                    } else {
                        showProAlert = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .foregroundColor(allowed ? .primary : .secondary)
                        if !allowed {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if model.id == current {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func store(kind: CuratedModelKind, id: String) {
        switch kind {
        case .text: selection.setTextModel(id)
        case .vision: selection.setVisionModel(id)
        }
    }
}
```

- [ ] **Step 2: 编译确认通过**

在 Xcode 选 `Notiee` scheme，`⌘B`。
Expected: BUILD SUCCEEDED（`ModelPickerView` 编译通过）。

- [ ] **Step 3: 手动核对（可选但推荐）**

Xcode Canvas 预览或跑模拟器进 ModelPickerView：文本区应显示 5 个模型、视觉区 3 个；免费档下只有 `DeepSeek v4-flash` 和 `Doubao-Seed-2.0-mini` 可点（右侧 √），其余带锁；点带锁的弹「Pro 专属模型」。

- [ ] **Step 4: 提交**

```bash
git add Notiee/Features/Settings/ModelPickerView.swift
git commit -m "feat(settings): ModelPickerView for free-version model selection"
```

---

## Task 3: 后端服务消费 selection（替换写死的模型）

**Files:**
- Modify: `Notiee/Services/BackendAIProcessingService.swift:17-18,53-54,86`
- Modify: `Notiee/Features/Spark/BackendSparkAIService.swift:18,145`

- [ ] **Step 1: 改 BackendAIProcessingService**

删除写死的静态常量（第 17-18 行）：

```swift
    /// Free-tier default models (must match the backend `MODEL_CATALOG` keys
    /// exactly). Pro model selection arrives in Phase 2; for now the free tier is
    /// locked to the cheapest vision + text models.
    static let freeVisionModel = "doubao-seed-2-0-mini"
    static let freeTextModel = "deepseek-v4-flash"
```

替换为（说明改为「读用户选择」）：

```swift
    /// 用户选中的模型（`CuratedModelSelection`，按当前档位夹取）。免费档实际仍
    /// 只会拿到免费模型；Phase 4 接真档位后 Pro 用户即可用到所选高级模型。
    private let selection = CuratedModelSelection.live
```

在 `func process` 里 `let preset = ScenePreset.load()` 之后，新增两行解析：

```swift
        let visionModel = selection.visionModelID(for: CurrentEntitlement.tier)
        let textModel = selection.textModelID(for: CurrentEntitlement.tier)
```

把 body 里的两行（原第 53-54 行）：

```swift
            "visionModel": Self.freeVisionModel,
            "textModel": Self.freeTextModel,
```

改为：

```swift
            "visionModel": visionModel,
            "textModel": textModel,
```

把 `parseStructuredNote` 的 `modelsUsed`（原第 86 行）：

```swift
            modelsUsed: [Self.freeVisionModel, Self.freeTextModel])
```

改为：

```swift
            modelsUsed: [visionModel, textModel])
```

- [ ] **Step 2: 改 BackendSparkAIService**

删除写死的静态常量（第 17-18 行）：

```swift
    /// Free-tier Spark model. Must match the backend `MODEL_CATALOG`.
    static let freeModel = "deepseek-v4-flash"
```

替换为：

```swift
    /// 用户选中的文本模型（与笔记处理共用同一份 `CuratedModelSelection`）。
    private let selection = CuratedModelSelection.live
```

把 `private func chat` 里的 body 构造（原第 145 行）：

```swift
        var body: [String: Any] = ["messages": messages, "model": Self.freeModel]
```

改为：

```swift
        let model = selection.textModelID(for: CurrentEntitlement.tier)
        var body: [String: Any] = ["messages": messages, "model": model]
```

- [ ] **Step 3: 编译确认通过**

Xcode 选 `Notiee` scheme，`⌘B`。
Expected: BUILD SUCCEEDED，且**无残留引用** `freeVisionModel` / `freeTextModel` / `freeModel`。核实：

```bash
grep -rn "freeVisionModel\|freeTextModel\|freeModel" Notiee
```
Expected: 无输出。

- [ ] **Step 4: 运行 Task 1 测试确认未回归**

`⌘U`（或只跑那两个测试类）。
Expected: `CuratedModelCatalogTests` + `CuratedModelSelectionTests` 仍全 PASS（默认值仍是 flash / mini，保证服务发的模型正确）。

- [ ] **Step 5: 提交**

```bash
git add Notiee/Services/BackendAIProcessingService.swift \
        Notiee/Features/Spark/BackendSparkAIService.swift
git commit -m "refactor(backend-services): consume CuratedModelSelection instead of hardcoded free models"
```

---

## Task 4: SettingsMainView 分叉（免费版进 ModelPicker、藏 BYOK 入口）

**Files:**
- Modify: `Notiee/Features/Settings/SettingsMainView.swift`（「大模型」Section ≈ :68 起；「高级设置」的「管理自定义模型」≈ :163 起）

> 共享文件，**只用 `#if NOTIEE_PLUS` 分叉**。改完必须验证 **两个 target 都能编译**、且 Notiee+ 表现不变。

- [ ] **Step 1: 「大模型」Section —— 用 `#if` 包住 BYOK 文本/视觉配置，`#else` 放 ModelPicker**

把这段（两个 `AIConfigurationView` 的 NavigationLink）：

```swift
                    NavigationLink {
                        AIConfigurationView(viewModel: viewModel, kind: .text)
                    } label: {
                        AIConfigurationRow(
                            title: AIModelKind.text.title,
                            systemImage: "text.bubble",
                            configuration: viewModel.textConfiguration
                        )
                    }

                    NavigationLink {
                        AIConfigurationView(viewModel: viewModel, kind: .vision)
                    } label: {
                        AIConfigurationRow(
                            title: AIModelKind.vision.title,
                            systemImage: "eye",
                            configuration: viewModel.visionConfiguration
                        )
                    }
```

替换为：

```swift
                    #if NOTIEE_PLUS
                    NavigationLink {
                        AIConfigurationView(viewModel: viewModel, kind: .text)
                    } label: {
                        AIConfigurationRow(
                            title: AIModelKind.text.title,
                            systemImage: "text.bubble",
                            configuration: viewModel.textConfiguration
                        )
                    }

                    NavigationLink {
                        AIConfigurationView(viewModel: viewModel, kind: .vision)
                    } label: {
                        AIConfigurationRow(
                            title: AIModelKind.vision.title,
                            systemImage: "eye",
                            configuration: viewModel.visionConfiguration
                        )
                    }
                    #else
                    NavigationLink {
                        ModelPickerView()
                    } label: {
                        Label("模型选择", systemImage: "cpu")
                    }
                    #endif
```

- [ ] **Step 2: 「大模型」Section —— 用 `#if` 包住「测试双端连接 + 状态 + 官方帮助文档」（免费版整块隐藏）**

把这段（`Button("测试双端连接")` 到 `DisclosureGroup("官方帮助文档") { ... }` 结束）：

```swift
                    Button("测试双端连接") {
                        viewModel.testConnection(for: .text)
                        viewModel.testConnection(for: .vision)
                    }
                    if viewModel.textConnectionTestStatus != .idle {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("文本模型：").font(.caption).foregroundStyle(.secondary)
                            ConnectionStatusView(status: viewModel.textConnectionTestStatus)
                        }
                    }
                    if viewModel.visionConnectionTestStatus != .idle {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("视觉模型：").font(.caption).foregroundStyle(.secondary)
                            ConnectionStatusView(status: viewModel.visionConnectionTestStatus)
                        }
                    }

                    DisclosureGroup("官方帮助文档") {
                        Link("阿里云百炼文档", destination: URL(string: "https://help.aliyun.com/zh/model-studio/")!)
                        Link("火山引擎文档", destination: URL(string: "https://www.volcengine.com/docs/82379/1399009")!)
                        Link("DeepSeek 文档", destination: URL(string: "https://api-docs.deepseek.com/zh-cn/")!)
                        Link("MiniMax 文档", destination: URL(string: "https://platform.minimaxi.com/docs/guides/text-generation")!)
                    }
```

替换为（前后各加一行 `#if NOTIEE_PLUS` / `#endif`）：

```swift
                    #if NOTIEE_PLUS
                    Button("测试双端连接") {
                        viewModel.testConnection(for: .text)
                        viewModel.testConnection(for: .vision)
                    }
                    if viewModel.textConnectionTestStatus != .idle {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("文本模型：").font(.caption).foregroundStyle(.secondary)
                            ConnectionStatusView(status: viewModel.textConnectionTestStatus)
                        }
                    }
                    if viewModel.visionConnectionTestStatus != .idle {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("视觉模型：").font(.caption).foregroundStyle(.secondary)
                            ConnectionStatusView(status: viewModel.visionConnectionTestStatus)
                        }
                    }

                    DisclosureGroup("官方帮助文档") {
                        Link("阿里云百炼文档", destination: URL(string: "https://help.aliyun.com/zh/model-studio/")!)
                        Link("火山引擎文档", destination: URL(string: "https://www.volcengine.com/docs/82379/1399009")!)
                        Link("DeepSeek 文档", destination: URL(string: "https://api-docs.deepseek.com/zh-cn/")!)
                        Link("MiniMax 文档", destination: URL(string: "https://platform.minimaxi.com/docs/guides/text-generation")!)
                    }
                    #endif
```

- [ ] **Step 3: 「高级设置」—— 免费版隐藏「管理自定义模型」**

把这段：

```swift
                NavigationLink {
                    CustomModelsListView(viewModel: viewModel)
                } label: {
                    Label("管理自定义模型", systemImage: "slider.horizontal.3")
                }
```

替换为：

```swift
                #if NOTIEE_PLUS
                NavigationLink {
                    CustomModelsListView(viewModel: viewModel)
                } label: {
                    Label("管理自定义模型", systemImage: "slider.horizontal.3")
                }
                #endif
```

- [ ] **Step 4: 编译两个 target 都通过（关键）**

Xcode：
1. 选 `Notiee` scheme → `⌘B` → 应 BUILD SUCCEEDED（免费版能看到「模型选择」入口）。
2. 选 `Notiee+` scheme → `⌘B` → 应 BUILD SUCCEEDED（Notiee+ 里 `ModelPickerView` 不参与编译；BYOK 配置、测试连接、帮助文档、管理自定义模型全部照旧）。

> 若 `Notiee+` scheme 不在列表：Product → Scheme → Manage Schemes… 勾选/新建 `Notiee+` 的 scheme，或直接选 `Notiee+` target 编译。两个 target 都必须过。

- [ ] **Step 5: 手动核对分叉正确**

- `Notiee`（免费）：设置 → 大模型 → 只有「模型选择」（无填 key 的文本/视觉配置、无测试连接、无官方文档）；高级设置里**没有**「管理自定义模型」。
- `Notiee+`（BYOK）：设置 → 大模型 → 文本/视觉配置、测试双端连接、官方帮助文档**全部照旧**；高级设置里「管理自定义模型」还在。

- [ ] **Step 6: 提交**

```bash
git add Notiee/Features/Settings/SettingsMainView.swift
git commit -m "feat(settings): free version shows ModelPicker, hides BYOK config and custom models"
```

---

## Self-Review（作者已核对）

**Spec 覆盖：** `CuratedModelCatalog`（Task 1）✅ / `ModelPickerView`（Task 2）✅ / `SettingsMainView` `#if` 分叉 + 藏自定义模型（Task 4）✅ / 免费版走精选目录被后端消费（Task 3）✅。`SparkSettingsView` 经核查无模型 UI，本 Phase 不改（范围说明已注明，Spark 档位锁走 Phase 2.5）。

**占位符扫描：** 无 TODO/「稍后实现」/空 catch。所有代码步骤均给出完整代码。

**类型一致性：** `ModelTier` / `CuratedModelKind` / `CuratedModel(id/displayName/kind/tier)` / `CuratedModelCatalog.{all,models(kind:),model(id:),isAllowed(_:for:),defaultModel(kind:for:)}` / `CuratedModelSelection.{textModelID(for:),visionModelID(for:),setTextModel(_:),setVisionModel(_:)}` / `CurrentEntitlement.tier` —— Task 1 定义、Task 2/3 调用签名一致。UDK 键 `selectedTextModel` / `selectedVisionModel` Task 1 定义、Task 1/3 使用一致。

**已知前提：** 档位硬编码 `.free`，故免费用户在 ModelPicker 里实际只能选中免费模型、Pro 模型恒加锁——符合 Phase 4 前的预期；Phase 4 只需把 `CurrentEntitlement.tier` 换成读 EntitlementStore，选择/夹取逻辑与 UI 无需改动。
