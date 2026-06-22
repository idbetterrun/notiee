# Spark 修复批次 + 模型/思考强度切换 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Spark 日期算错/「解析失败」、标题截断、发送键双层玻璃，并实现 Spark 独立的模型 + 思考强度切换。

**Architecture:** 日期靠新增确定性 `DateInfoTool`（Agent 工具）解决，并健壮化 `callAgent` 解析；标题移到内容区自定义 header；发送键改单层玻璃；模型/思考强度走 Spark 专属持久化覆盖（不动全局 `.text` 配置），思考参数经 per-provider `ThinkingCapability` 注入 API payload。纯逻辑走 XCTest，UI 走 iOS 26 build + 肉眼。

**Tech Stack:** Swift 6 / SwiftUI / XCTest / iOS 26 SDK，部署目标 iOS 18。

**对应 spec:** `docs/superpowers/specs/2026-06-22-spark-fixes-model-switcher-design.md`

---

## 通用命令

模拟器 **iPhone 17 Pro**（iOS 26，已启动）。

测试：
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NotieeTests/<Class> 2>&1 | tail -20
```
构建：
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
> 新建 `.swift` 文件必须加入对应 target（`Notiee.xcodeproj/project.pbxproj` 四处：PBXFileReference / PBXBuildFile / group children / Sources build phase），mirror 近期新增文件（如 `ScheduleUpdateTool.swift`）。**pbxproj UUID 必须全局唯一**——新加前 `grep -c <前缀> Notiee.xcodeproj/project.pbxproj` 确认未占用。

---

## Task 1: 发送键单层实心玻璃（#3）

**Files:**
- Modify: `Notiee/Features/Spark/SparkInputBar.swift:37-54`

- [ ] **Step 1: 改发送按钮为单层**
读真实代码。当前发送按钮（`SparkInputBar.swift:38-54`）为：内层 `.background(... in: Circle())` + 外层 `.glassIconButton(prominent:)`（双层）。替换该 Button 段为单层实心玻璃圆：
```swift
            let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button(action: { isLoading ? onStop() : onSubmit() }) {
                Group {
                    if isLoading {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 14, weight: .semibold))
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(isEmpty && !isLoading ? Color(.systemGray4) : accentColor, in: Circle())
            }
            .disabled(isEmpty && !isLoading)
            .padding(.trailing, 6)
```
即：删除 `.glassIconButton(prominent: !isEmpty || isLoading)` 这一行（去掉外层玻璃），保留单一实心 `Circle` 背景。其余（disabled、padding、点击逻辑）不变。

- [ ] **Step 2: 构建**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`（运行肉眼：发送键为单层实心圆，loading 显示 stop.fill）。

- [ ] **Step 3: Commit**
```bash
git add Notiee/Features/Spark/SparkInputBar.swift
git commit -m "fix(spark): single-layer solid send button (remove double glass)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: 标题移到内容区自定义 header（#2）

**Files:**
- Modify: `Notiee/Features/Spark/SparkView.swift`（移除 toolbar leading 标题项；在 `contentView` 顶部加 header）

- [ ] **Step 1: 移除 toolbar leading 标题项**
读 `SparkView.swift:41-58`。删除整个 `ToolbarItem(placement: .topBarLeading) { HStack(spacing: 6) { ... } }`（含 currentTitle/beta/spinner）。保留 `.navigationBarTitleDisplayMode(.inline)` 与 `ToolbarItemGroup(placement: .topBarTrailing) { ... }` 两按钮不变。

- [ ] **Step 2: 加自定义 header，并在 contentView 顶部插入**
在 `SparkView` 加一个计算属性：
```swift
    private var titleHeader: some View {
        HStack(spacing: 6) {
            Text(viewModel.currentTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if viewModel.messages.isEmpty {
                Text("beta")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)))
            } else if viewModel.isGeneratingTitle {
                ProgressView().scaleEffect(0.6)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
```
把 `contentView`（`SparkView.swift:106-118`）改为在顶部叠加该 header：
```swift
    @ViewBuilder
    private var contentView: some View {
        VStack(spacing: 0) {
            titleHeader
            if viewModel.messages.isEmpty {
                VStack {
                    Spacer()
                    greetingView
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chatScrollView
            }
        }
    }
```
读真实代码确认 `greetingView`/`chatScrollView` 名称一致后替换。

- [ ] **Step 3: 构建**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`（运行肉眼：标题靠左、单行不截断、beta/spinner 在右；右上角两按钮保留；标题不再被压成「周...」）。

- [ ] **Step 4: Commit**
```bash
git add Notiee/Features/Spark/SparkView.swift
git commit -m "fix(spark): move title to in-content header (no toolbar truncation)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: DateInfoTool（确定性日期/星期几工具）（#1a）

**Files:**
- Create: `Notiee/Features/Spark/Agent/Tools/DateInfoTool.swift`
- Create: `NotieeTests/DateInfoToolTests.swift`

- [ ] **Step 1: 读 sibling 确认真实 API**
读 `Notiee/Features/Spark/Agent/Tools/ScheduleUpdateTool.swift` 与 `CalendarQueryTool.swift`，确认 `AgentTool` 协议成员、`AgentToolParametersSchema`/`AgentToolProperty` 初始化器、`AgentToolResult(success:message:data:undoAction:)`、`AgentToolError.missingParameter`、以及 `CalendarQueryTool.parseDate(_:)` 的真实签名（下方代码按上批确认的形态书写；若有出入以真实为准）。

- [ ] **Step 2: 写失败测试 `NotieeTests/DateInfoToolTests.swift`**
```swift
import XCTest
@testable import Notiee

@MainActor
final class DateInfoToolTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func makeTool() -> DateInfoTool {
        DateInfoTool(now: { self.cal.date(from: DateComponents(year: 2026, month: 6, day: 22))! },
                     calendar: self.cal)
    }

    func testExplicitDate_weekday() async throws {
        let r = try await makeTool().execute(parameters: ["date": "2026-06-24"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.message.contains("星期三"), "2026-06-24 应为星期三，实际: \(r.message)")
    }

    func testToday() async throws {
        let r = try await makeTool().execute(parameters: ["date": "today"])
        XCTAssertTrue(r.success)
        XCTAssertTrue(r.message.contains("星期一"), "2026-06-22 应为星期一，实际: \(r.message)")
    }

    func testOffsetDays() async throws {
        let r = try await makeTool().execute(parameters: ["date": "2026-06-24"])
        XCTAssertEqual(r.data?["offset_days"] as? Int, 2)
    }

    func testMissingParam_throws() async {
        do { _ = try await makeTool().execute(parameters: [:]); XCTFail("应抛出") }
        catch {}
    }

    func testUnparseable_returnsFailure() async throws {
        let r = try await makeTool().execute(parameters: ["date": "随便写点啥"])
        XCTAssertFalse(r.success)
    }
}
```

- [ ] **Step 3: 运行确认失败**
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NotieeTests/DateInfoToolTests 2>&1 | tail -20
```
Expected: 编译失败 `cannot find 'DateInfoTool'`.

- [ ] **Step 4: 实现 `Notiee/Features/Spark/Agent/Tools/DateInfoTool.swift`**
```swift
import Foundation

@MainActor
final class DateInfoTool: AgentTool {
    let name = "date_info"
    let description = "查询某个日期是星期几、对应的标准日期(yyyy-MM-dd)、以及距今天的天数。凡涉及'某天星期几'或相对日期换算，必须调用本工具，不要自行心算。"
    let permission: AgentToolPermission = .read

    let parametersSchema = AgentToolParametersSchema(
        properties: [
            "date": AgentToolProperty(type: "string",
                description: "日期，可为 today/tomorrow、yyyy-MM-dd、ISO8601，或中文相对表达如 今天/明天/后天/下周三",
                enumValues: nil, items: nil)
        ],
        required: ["date"]
    )

    private let now: () -> Date
    private let calendar: Calendar

    init(now: @escaping () -> Date = { Date() }, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.now = now
        self.calendar = calendar
    }

    func execute(parameters: [String: Any]) async throws -> AgentToolResult {
        guard let raw = parameters["date"] as? String, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AgentToolError.missingParameter("date")
        }
        guard let date = resolve(raw) else {
            return AgentToolResult(success: false,
                message: "无法解析日期「\(raw)」，请给出明确日期（如 2026-06-24）。",
                data: nil, undoAction: nil)
        }
        let today = calendar.startOfDay(for: now())
        let target = calendar.startOfDay(for: date)
        let offset = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        let iso = isoString(target)
        let weekday = weekdayName(target)
        let rel: String
        switch offset {
        case 0: rel = "就是今天"
        case 1: rel = "1 天后"
        case -1: rel = "1 天前"
        case let d where d > 0: rel = "\(d) 天后"
        default: rel = "\(-offset) 天前"
        }
        return AgentToolResult(success: true,
            message: "\(iso) 是\(weekday)，\(rel)。",
            data: ["iso": iso, "weekday": weekday, "offset_days": offset],
            undoAction: nil)
    }

    private func resolve(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let todayStart = calendar.startOfDay(for: now())
        switch s {
        case "today", "今天": return todayStart
        case "tomorrow", "明天": return calendar.date(byAdding: .day, value: 1, to: todayStart)
        case "后天": return calendar.date(byAdding: .day, value: 2, to: todayStart)
        case "yesterday", "昨天": return calendar.date(byAdding: .day, value: -1, to: todayStart)
        default:
            return CalendarQueryTool.parseDate(raw)
        }
    }

    private func isoString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func weekdayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale.current
        f.dateFormat = "EEEE"
        return f.string(from: date)
    }
}
```
> 说明：测试断言「星期三/星期一」依赖测试宿主语言为中文（zh-Hant 下为「星期三」同字、英文为 Wednesday）。本仓库测试宿主解析为 zh-Hant（上批已知），故 `EEEE` 输出「星期三」。若实际宿主语言不同导致断言不符，按宿主输出调整断言（与上批 greeting 测试同理），而非改 weekday 逻辑。

- [ ] **Step 5: 注册测试文件到 NotieeTests target、工具文件到 Notiee target；运行测试**
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NotieeTests/DateInfoToolTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（5 测试）。若 weekday 断言因宿主语言不符，改断言为宿主实际输出后再绿。

- [ ] **Step 6: Commit**
```bash
git add Notiee/Features/Spark/Agent/Tools/DateInfoTool.swift NotieeTests/DateInfoToolTests.swift Notiee.xcodeproj/project.pbxproj
git commit -m "feat(agent): DateInfoTool for deterministic weekday/date resolution

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: 注册 DateInfoTool + 元数据 + prompt 硬规则（#1a）

**Files:**
- Modify: `Notiee/Features/Spark/SparkViewModel.swift`（makeAgentExecutor tools）
- Modify: `Notiee/Features/Spark/Agent/AgentToolPresentation.swift`
- Modify: `Notiee/Features/Spark/SparkPromptFragments.swift`

- [ ] **Step 1: 注册工具**
在 `makeAgentExecutor()` tools 数组里（紧邻 `ScheduleUpdateTool(calendarManager: calendarManager),` 之后或 CalendarQueryTool 附近）加：
```swift
            DateInfoTool(),
```
读真实代码定位 tools 数组与缩进。

- [ ] **Step 2: AgentToolPresentation 加 date_info**
在 `AgentToolPresentation.forName` 的某个 `case` 之后加：
```swift
        case "date_info":
            return .init(icon: "calendar", displayName: "查日期", runningText: "正在查日期…")
```
匹配真实返回类型初始化器形态（mirror 现有 `schedule_update` case）。

- [ ] **Step 3: prompt 能力清单 + 硬规则**
在 `SparkPromptFragments.agentSystemPrompt` 能力清单加一行：
```
        - 查询日期/星期几（用 date_info 工具）
```
并在行为准则里加一条（编号顺延，放在第 8 条"当前时间"之后）：
```
        9. 凡涉及"某个日期是星期几"、或"下周X/N天后是哪天"等日期换算，必须调用 date_info 工具获取准确结果，严禁自行心算星期几或日期。
```
读真实代码确认编号与缩进。

- [ ] **Step 4: 构建**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**
```bash
git add Notiee/Features/Spark/SparkViewModel.swift Notiee/Features/Spark/Agent/AgentToolPresentation.swift Notiee/Features/Spark/SparkPromptFragments.swift
git commit -m "feat(agent): register DateInfoTool, presentation + must-use-tool rule

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: callAgent 解析健壮化（#1b）

**Files:**
- Modify: `Notiee/Services/AIAPIClient.swift`（`OpenAICaller.callAgent` 约 69-74；`AnthropicCaller.callAgent` 对应处）

> **先用 systematic-debugging 复现**：构造一个 `choices[0].message.content == null` 且含 `reasoning_content`、或缺 `usage` 的响应 JSON，确认现状会抛 `AIError.parsingFailed`。再按下方改。

- [ ] **Step 1: 健壮化 OpenAICaller.callAgent**
读 `AIAPIClient.swift:38-81`。把 69-74 的 guard 改为：HTTP 2xx 已通过的前提下，宽松提取 message：
```swift
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = (json?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
        // content 可能为 null（如 reasoning-only 中间态）；不因此抛错
        let text = (message?["content"] as? String) ?? ""
        let toolCalls = (message?["tool_calls"] as? [[String: Any]]) ?? []
        let tokens = (json?["usage"] as? [String: Any])?["total_tokens"] as? Int ?? 0

        // 仅当连结构都解析不出（既无 message 又无 toolCalls 又无文本）才报错，且带原始片段便于诊断
        if message == nil && toolCalls.isEmpty && text.isEmpty {
            let snippet = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw AIError.apiError("Unexpected response: \(snippet)")
        }
        return (text, toolCalls, tokens)
```
（删除原 `guard let json ... else { throw AIError.parsingFailed }` 与其后单独的 text/toolCalls/tokens 提取行，用上面整段替换。）

- [ ] **Step 2: AnthropicCaller.callAgent 同样宽松化**
读 `AIAPIClient.swift:162-216`。若其 parse 也存在"取不到结构即 `parsingFailed`"，做同样处理：content 为空不抛错，仅在完全无法解析时抛带片段的 `apiError`。保持 Anthropic 响应字段（`content`/`tool_use`）的真实结构。

- [ ] **Step 3: 构建 + 跑相关测试**
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NotieeTests/SparkViewModelTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`，构建通过。（运行肉眼：Agent 模式下问"24号星期几"会调用 date_info 给出周三，不再报"返回结果解析失败"。）

- [ ] **Step 4: Commit**
```bash
git add Notiee/Services/AIAPIClient.swift
git commit -m "fix(spark): tolerate non-standard agent responses (no spurious parse-fail)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: WebFetch 刷新预设模型列表（#4-D2）

**Files:**
- Modify: `Notiee/Models/AIProvider.swift`（`predefinedModels`）

- [ ] **Step 1: WebFetch 校正各家当前 model id**
逐家抓官方文档，记录确切可用的 chat model id（OpenAI 兼容 `model` 字段值）：
- DeepSeek: `https://api-docs.deepseek.com/quick_start/pricing`
- Qwen: `https://help.aliyun.com/zh/model-studio/models`
- Doubao: `https://www.volcengine.com/docs/82379/1330310`（若抓取为空，用 WebSearch 校正）
- MiniMax: `https://platform.minimax.io/docs/release-notes/models`

- [ ] **Step 2: 更新 `predefinedModels`**
按抓取结果更新 `AIProvider.swift:65-78`。以 2026-06 研究为默认（抓取确认后定稿）：
```swift
    var predefinedModels: [String] {
        switch self {
        case .qwenText:
            return ["qwen3.5-plus", "qwen-plus", "qwen-max", "qwen-turbo"]
        case .qwenVision:
            return ["qwen-vl-plus", "qwen-vl-max"]
        case .deepseek:
            return ["deepseek-v4-pro", "deepseek-v4-flash", "deepseek-chat", "deepseek-reasoner"]
        case .minimax:
            return ["MiniMax-M3", "MiniMax-M2.7"]
        case .doubaoText:
            return ["doubao-seed-2-0-pro", "doubao-seed-2-0-lite", "doubao-seed-2-0-mini"]
        default:
            return []
        }
    }
```
> 注：上方为研究默认值；以 Step 1 抓取的确切 id 为准修正（Doubao 常带日期后缀如 `-260215`，需用文档确切值；deepseek 旧名保留为兼容项）。

- [ ] **Step 3: 构建**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**
```bash
git add Notiee/Models/AIProvider.swift
git commit -m "feat(ai): refresh predefined model lists (2026-06, verified via docs)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: ThinkingCapability（per-provider 思考参数）（#4-D3）

**Files:**
- Create: `Notiee/Models/ThinkingCapability.swift`
- Create: `NotieeTests/ThinkingCapabilityTests.swift`

- [ ] **Step 1: WebFetch 校正各家思考参数**（已知：Qwen `enable_thinking`+`thinking_budget`；Doubao `reasoning_effort` minimal/low/medium/high；DeepSeek V4 思考由请求参数控制；OpenAI 兼容自定义 `reasoning_effort`）。对 DeepSeek/MiniMax 抓官方文档确认确切参数名/取值。

- [ ] **Step 2: 写失败测试 `NotieeTests/ThinkingCapabilityTests.swift`**
```swift
import XCTest
@testable import Notiee

final class ThinkingCapabilityTests: XCTestCase {
    func testDoubao_hasEffortLevels() {
        let cap = ThinkingCapability.forProvider(.doubaoText)
        XCTAssertFalse(cap.levels.isEmpty)
    }

    func testDoubao_applyHighInjectsReasoningEffort() {
        let cap = ThinkingCapability.forProvider(.doubaoText)
        guard let high = cap.levels.first(where: { $0.id == "high" }) else { return XCTFail("缺 high") }
        var payload: [String: Any] = ["model": "x"]
        cap.apply(level: high, to: &payload)
        XCTAssertEqual(payload["reasoning_effort"] as? String, "high")
    }

    func testQwen_applyOnInjectsEnableThinking() {
        let cap = ThinkingCapability.forProvider(.qwenText)
        guard let on = cap.levels.first(where: { $0.id != "off" }) else { return XCTFail("缺 on 档") }
        var payload: [String: Any] = ["model": "x"]
        cap.apply(level: on, to: &payload)
        XCTAssertEqual(payload["enable_thinking"] as? Bool, true)
    }

    func testQwen_applyOffDisablesThinking() {
        let cap = ThinkingCapability.forProvider(.qwenText)
        guard let off = cap.levels.first(where: { $0.id == "off" }) else { return XCTFail("缺 off") }
        var payload: [String: Any] = [:]
        cap.apply(level: off, to: &payload)
        XCTAssertEqual(payload["enable_thinking"] as? Bool, false)
    }

    func testVision_noThinking() {
        XCTAssertTrue(ThinkingCapability.forProvider(.qwenVision).levels.isEmpty)
    }
}
```

- [ ] **Step 3: 运行确认失败**
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NotieeTests/ThinkingCapabilityTests 2>&1 | tail -20
```
Expected: 编译失败 `cannot find 'ThinkingCapability'`.

- [ ] **Step 4: 实现 `Notiee/Models/ThinkingCapability.swift`**
```swift
import Foundation

struct ThinkingLevel: Identifiable, Equatable, Sendable {
    let id: String        // "off"/"minimal"/"low"/"medium"/"high"/"on"
    let displayName: String
}

struct ThinkingCapability: Sendable {
    let levels: [ThinkingLevel]
    private let injector: @Sendable (ThinkingLevel, inout [String: Any]) -> Void

    func apply(level: ThinkingLevel, to payload: inout [String: Any]) {
        injector(level, &payload)
    }

    static func forProvider(_ provider: AIProviderType) -> ThinkingCapability {
        switch provider {
        case .doubaoText, .custom, .minimax:
            // OpenAI 兼容 reasoning_effort（Doubao 已确认；custom/minimax 以确认为准）
            let levels = [
                ThinkingLevel(id: "minimal", displayName: String(localized: "极简思考")),
                ThinkingLevel(id: "low", displayName: String(localized: "低强度思考")),
                ThinkingLevel(id: "medium", displayName: String(localized: "中强度思考")),
                ThinkingLevel(id: "high", displayName: String(localized: "高强度思考"))
            ]
            return ThinkingCapability(levels: levels) { level, payload in
                payload["reasoning_effort"] = level.id
            }
        case .qwenText:
            let levels = [
                ThinkingLevel(id: "off", displayName: String(localized: "关闭思考")),
                ThinkingLevel(id: "on", displayName: String(localized: "开启思考"))
            ]
            return ThinkingCapability(levels: levels) { level, payload in
                payload["enable_thinking"] = (level.id != "off")
            }
        case .deepseek:
            // DeepSeek V4：思考为请求参数开/关（确切键名以 WebFetch 确认；下方为 OpenAI 兼容默认）
            let levels = [
                ThinkingLevel(id: "off", displayName: String(localized: "关闭思考")),
                ThinkingLevel(id: "on", displayName: String(localized: "开启思考"))
            ]
            return ThinkingCapability(levels: levels) { level, payload in
                payload["reasoning_effort"] = (level.id == "off") ? "minimal" : "high"
            }
        case .qwenVision, .doubaoVision:
            return ThinkingCapability(levels: []) { _, _ in }
        }
    }
}
```
> 注：Qwen 若需 `thinking_budget` 多档，可后续扩 levels；本批先做开/关满足"强度"控制。DeepSeek 键名以 Step 1 抓取确认后修正（保持 levels 结构不变）。

- [ ] **Step 5: 注册文件 + 跑测试**
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NotieeTests/ThinkingCapabilityTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（5 测试）。

- [ ] **Step 6: Commit**
```bash
git add Notiee/Models/ThinkingCapability.swift NotieeTests/ThinkingCapabilityTests.swift Notiee.xcodeproj/project.pbxproj
git commit -m "feat(ai): per-provider ThinkingCapability (payload injection)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Spark 模型/思考强度持久化覆盖（#4-D1）

**Files:**
- Modify: `Notiee/Utils/UserDefaultsKeys.swift`
- Create: `Notiee/Features/Spark/SparkModelPreferences.swift`
- Create: `NotieeTests/SparkModelPreferencesTests.swift`

- [ ] **Step 1: 加 UDK keys**
在 `UDK` 的 Spark 区（约 `UserDefaultsKeys.swift:81-85` 附近）加：
```swift
    static let sparkModelOverride = "spark_model_override"
    static let sparkThinkingLevel = "spark_thinking_level"
```

- [ ] **Step 2: 写失败测试 `NotieeTests/SparkModelPreferencesTests.swift`**
```swift
import XCTest
@testable import Notiee

final class SparkModelPreferencesTests: XCTestCase {
    private func makePrefs() -> SparkModelPreferences {
        let ud = UserDefaults(suiteName: "test.sparkprefs.\(UUID().uuidString)")!
        return SparkModelPreferences(userDefaults: ud)
    }

    func testEffectiveModel_fallsBackToGlobalWhenNoOverride() {
        let p = makePrefs()
        XCTAssertEqual(p.effectiveModelName(globalModel: "qwen-plus"), "qwen-plus")
    }

    func testEffectiveModel_usesOverride() {
        let p = makePrefs()
        p.setModelOverride("deepseek-v4-pro")
        XCTAssertEqual(p.effectiveModelName(globalModel: "qwen-plus"), "deepseek-v4-pro")
    }

    func testThinkingLevel_persists() {
        let p = makePrefs()
        p.setThinkingLevelID("high")
        XCTAssertEqual(p.thinkingLevelID, "high")
    }

    func testClearOverride_fallsBack() {
        let p = makePrefs()
        p.setModelOverride("x")
        p.setModelOverride("")   // 空视为清除
        XCTAssertEqual(p.effectiveModelName(globalModel: "g"), "g")
    }
}
```

- [ ] **Step 3: 运行确认失败**
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NotieeTests/SparkModelPreferencesTests 2>&1 | tail -20
```
Expected: 编译失败 `cannot find 'SparkModelPreferences'`.

- [ ] **Step 4: 实现 `Notiee/Features/Spark/SparkModelPreferences.swift`**
```swift
import Foundation

final class SparkModelPreferences {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var modelOverride: String {
        userDefaults.string(forKey: UDK.sparkModelOverride) ?? ""
    }

    func setModelOverride(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            userDefaults.removeObject(forKey: UDK.sparkModelOverride)
        } else {
            userDefaults.set(trimmed, forKey: UDK.sparkModelOverride)
        }
    }

    func effectiveModelName(globalModel: String) -> String {
        modelOverride.isEmpty ? globalModel : modelOverride
    }

    var thinkingLevelID: String? {
        userDefaults.string(forKey: UDK.sparkThinkingLevel)
    }

    func setThinkingLevelID(_ id: String) {
        userDefaults.set(id, forKey: UDK.sparkThinkingLevel)
    }
}
```

- [ ] **Step 5: 注册文件 + 跑测试**
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NotieeTests/SparkModelPreferencesTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`（4 测试）。

- [ ] **Step 6: Commit**
```bash
git add Notiee/Utils/UserDefaultsKeys.swift Notiee/Features/Spark/SparkModelPreferences.swift NotieeTests/SparkModelPreferencesTests.swift Notiee.xcodeproj/project.pbxproj
git commit -m "feat(spark): SparkModelPreferences (Spark-local model + thinking override)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: API caller 接思考参数 + SparkAIService 接 Spark 覆盖（#4-D4）

**Files:**
- Modify: `Notiee/Services/AIAPIClient.swift`（`OpenAICaller.callAgent`/`callText` 加可选 reasoning 注入）
- Modify: `Notiee/Features/Spark/SparkAIService.swift`（agentChat/ask 用 effectiveModelName + thinking）

- [ ] **Step 1: caller 加可选注入参数**
给 `OpenAICaller.callAgent` 和 `callText` 各加一个可选末位参数 `extraBody: [String: Any] = [:]`，在构造 `payload` 后合并：
```swift
        for (k, v) in extraBody { payload[k] = v }
```
（`callAgent` 在 `AIAPIClient.swift:43` 的 payload 初始化之后、`if !tools.isEmpty` 之前合并；`callText` 在其 payload 构造后合并。读真实代码精确插入。）保持默认 `[:]` 时行为与现状完全一致。

- [ ] **Step 2: SparkAIService 计算 effectiveModel + thinking 并传入**
读 `SparkAIService.swift`。在类内加 `private let modelPrefs = SparkModelPreferences()`。在 `agentChat`（约 530）与 `ask`（约 141）里，构造一个 helper：
```swift
    private func sparkModelAndExtraBody(_ textConfig: AIModelConfiguration) -> (model: String, extra: [String: Any]) {
        let model = modelPrefs.effectiveModelName(globalModel: textConfig.modelName)
        var extra: [String: Any] = [:]
        let cap = ThinkingCapability.forProvider(textConfig.providerType)
        if let id = modelPrefs.thinkingLevelID, let level = cap.levels.first(where: { $0.id == id }) {
            cap.apply(level: level, to: &extra)
        }
        return (model, extra)
    }
```
调用前先 `let (m, extra) = sparkModelAndExtraBody(textConfig)`。**模型名覆盖 `model: m` 应用到两个协议分支**（OpenAI 与 Anthropic 都把 `model:` 从 `textConfig.modelName` 改为 `m`，因为 Spark 模型覆盖与协议无关）。**思考注入 `extraBody: extra` 仅加在 OpenAI 协议分支**（Anthropic `callAgent`/`callText` 本批不接 extraBody，符合 spec「thinking 仅覆盖 OpenAI 兼容 provider」）。读真实代码逐处替换 model 参数。

- [ ] **Step 3: 构建 + 跑 Spark 测试**
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:NotieeTests/SparkViewModelTests 2>&1 | tail -20
```
Expected: `** TEST SUCCEEDED **`，构建通过。

- [ ] **Step 4: Commit**
```bash
git add Notiee/Services/AIAPIClient.swift Notiee/Features/Spark/SparkAIService.swift
git commit -m "feat(spark): apply Spark model override + thinking effort to OpenAI calls

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Spark 模型 + 思考强度 UI 胶囊（#4-D5）

**Files:**
- Create: `Notiee/Features/Spark/SparkModelChip.swift`
- Modify: `Notiee/Features/Spark/SparkView.swift`（bottom bar HStack）
- Modify: `Notiee/Features/Spark/SparkViewModel.swift`（暴露 prefs/可选模型/思考档）

- [ ] **Step 1: SparkViewModel 暴露所需状态**
读 `SparkViewModel.swift`。加（@Published 或计算属性）：
```swift
    @Published var sparkModelOverride: String = SparkModelPreferences().modelOverride
    @Published var sparkThinkingLevelID: String? = SparkModelPreferences().thinkingLevelID

    private let modelPrefs = SparkModelPreferences()

    var availableModels: [String] {
        let cfg = settingsStore.loadConfiguration(for: .text)
        return cfg.providerType == .custom ? [cfg.modelName].filter { !$0.isEmpty } : cfg.providerType.predefinedModels
    }
    var effectiveModelName: String {
        let cfg = settingsStore.loadConfiguration(for: .text)
        return modelPrefs.effectiveModelName(globalModel: cfg.modelName)
    }
    var thinkingLevels: [ThinkingLevel] {
        ThinkingCapability.forProvider(settingsStore.loadConfiguration(for: .text).providerType).levels
    }
    func selectModel(_ name: String) {
        modelPrefs.setModelOverride(name); sparkModelOverride = modelPrefs.modelOverride
    }
    func selectThinkingLevel(_ id: String) {
        modelPrefs.setThinkingLevelID(id); sparkThinkingLevelID = id
    }
```
确认 `settingsStore` 在 ViewModel 可访问（读真实代码；若 ViewModel 没有 settingsStore，用 `UserDefaultsAppSettingsStore.live` 或 SparkAIService 暴露的访问点；按真实结构调整）。

- [ ] **Step 2: 创建 `Notiee/Features/Spark/SparkModelChip.swift`**
```swift
import SwiftUI

struct SparkModelChip: View {
    let title: String
    let icon: String
    let options: [(id: String, label: String)]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.id) { opt in
                Button {
                    onSelect(opt.id)
                } label: {
                    if opt.id == selectedID {
                        Label(opt.label, systemImage: "checkmark")
                    } else {
                        Text(opt.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(Color.secondary)
            .glassSurface(in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 3: 在 bottom bar 放两个胶囊（agent chip 右侧）**
读 `SparkView.swift:146-152`。把 agent chip 那个 HStack 改为：
```swift
            HStack(spacing: 8) {
                SparkAgentChip(isOn: $viewModel.isAgentModeEnabled)

                if !viewModel.availableModels.isEmpty {
                    SparkModelChip(
                        title: viewModel.effectiveModelName,
                        icon: "cpu",
                        options: viewModel.availableModels.map { ($0, $0) },
                        selectedID: viewModel.effectiveModelName,
                        onSelect: { viewModel.selectModel($0) }
                    )
                }

                if !viewModel.thinkingLevels.isEmpty {
                    SparkModelChip(
                        title: thinkingTitle,
                        icon: "brain",
                        options: viewModel.thinkingLevels.map { ($0.id, $0.displayName) },
                        selectedID: viewModel.sparkThinkingLevelID,
                        onSelect: { viewModel.selectThinkingLevel($0) }
                    )
                }

                Spacer()
            }
            .padding(.leading, 48)
            .padding(.trailing, 24)
            .padding(.bottom, 2)
```
并在 `SparkView` 加：
```swift
    private var thinkingTitle: String {
        if let id = viewModel.sparkThinkingLevelID,
           let lvl = viewModel.thinkingLevels.first(where: { $0.id == id }) {
            return lvl.displayName
        }
        return String(localized: "思考强度")
    }
```
（窄屏可省略文字——若挤压，给 model chip 加 `.lineLimit(1)` 已含；必要时 model chip 文字 `.truncationMode(.middle)`。）

- [ ] **Step 4: 注册 SparkModelChip 文件 + 构建**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`（运行肉眼：agent chip 右侧出现"当前模型"与"思考强度"胶囊；点击切换；不支持思考的 provider 不显示思考胶囊；切换不影响拍记处理模型）。

- [ ] **Step 5: Commit**
```bash
git add Notiee/Features/Spark/SparkModelChip.swift Notiee/Features/Spark/SparkView.swift Notiee/Features/Spark/SparkViewModel.swift Notiee.xcodeproj/project.pbxproj
git commit -m "feat(spark): model + thinking-intensity chips next to agent toggle

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: i18n 三语补全（#E）

**Files:**
- Modify: `Notiee/en.lproj/Localizable.strings`、`zh-Hans.lproj`、`zh-Hant.lproj`

- [ ] **Step 1: 盘点新文案**
本批新增用户可见中文字面量：`查日期`、`正在查日期…`、`思考强度`、`关闭思考`、`开启思考`、`极简思考`、`低强度思考`、`中强度思考`、`高强度思考`。追加前各文件 grep 确认未存在。

- [ ] **Step 2: 三份文件追加（仅缺失项）**
en 示例：
```
/* Spark model/thinking batch */
"查日期" = "Date info";
"正在查日期…" = "Looking up date…";
"思考强度" = "Reasoning";
"关闭思考" = "No thinking";
"开启思考" = "Thinking on";
"极简思考" = "Minimal";
"低强度思考" = "Low";
"中强度思考" = "Medium";
"高强度思考" = "High";
```
zh-Hans 同源（key==value）；zh-Hant 繁体（如 `關閉思考`/`開啟思考`/`思考強度` 等）。

- [ ] **Step 3: lint + 构建**
```bash
plutil -lint Notiee/en.lproj/Localizable.strings Notiee/zh-Hans.lproj/Localizable.strings Notiee/zh-Hant.lproj/Localizable.strings
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -10
```
Expected: 三份 `OK`，`** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**
```bash
git add Notiee/en.lproj/Localizable.strings Notiee/zh-Hans.lproj/Localizable.strings Notiee/zh-Hant.lproj/Localizable.strings
git commit -m "i18n: localize Spark model/thinking batch strings

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 12: 全量回归 + 冒烟

- [ ] **Step 1: 全测试套件**
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -30
```
Expected: 除既有 `RecordManagerTests.testCapturePhotoStoresRecordAndPersists`（已知失败）外全绿。

- [ ] **Step 2: iOS 26 模拟器冒烟清单**
- [ ] 发送键：单层实心玻璃圆；loading 变 stop，可中止
- [ ] 标题：靠左单行不截断、beta/spinner 在右；右上角两按钮保留
- [ ] Agent：问"6月24日星期几"会调用 date_info 返回**周三**；不再报"返回结果解析失败"
- [ ] Agent：问"下周三是哪天/N天后"也走 date_info
- [ ] 模型胶囊：显示当前模型；点击可切到同 provider 其他模型；切换不改拍记/照片处理模型
- [ ] 思考胶囊：支持思考的 provider 才显示；切档生效；vision/不支持的 provider 不显示
- [ ] 设置页换 provider 后，Spark 模型/思考选项随之更新

---

## 自审（spec 覆盖）

| spec 项 | 任务 |
|---------|------|
| A1 DateInfoTool | Task 3, 4 |
| A2 callAgent 健壮化 | Task 5 |
| B 标题自定义 header | Task 2 |
| C 发送键单层玻璃 | Task 1 |
| D1 Spark 持久化覆盖 | Task 8 |
| D2 预设模型刷新 | Task 6 |
| D3 ThinkingCapability | Task 7 |
| D4 API 管线接思考 | Task 9 |
| D5 UI 胶囊 | Task 10 |
| E i18n | Task 11 |
| 回归冒烟 | Task 12 |
