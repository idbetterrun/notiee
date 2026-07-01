# Spark 修复批次 + 模型/思考强度切换 Design

> 日期：2026-06-22 · 分支基线：`feature/ai-agent`

## 背景与目标

针对 Spark 当前四类问题：

1. **日期/星期几算错 + Agent「解析失败」**：模型自行心算星期几出错（2026-06-24 实为周三，模型答周六）；且在 Agent 模式下问"非工具"问题时报「Agent 执行出错：返回结果解析失败」。
2. **标题缩成一坨**：导航栏 `topBarLeading` 里的标题被系统压窄，截断成「周...」。
3. **发送键双层玻璃**：发送按钮叠了实心圆 + 外层玻璃，视觉是两层。
4. **缺少模型/思考强度切换**：用户接了某家 API 后无法在 Spark 内切换该 API 下其他模型，也没有思考强度控制。

目标：四项全部修复/实现，UI 走 iOS 26 build + 肉眼，纯逻辑走 XCTest。

## 现状（已核对代码）

- **Prompt**：`SparkPromptFragments.agentSystemPrompt(now:)` 已注入 `now.formatted(date: .complete, time: .shortened)`（含今天星期几）。问题是模型对**其他**日期自行心算星期几。
- **Agent「解析失败」**：`AgentExecutor.run` 对"无 tool call"已优雅处理（`AgentExecutor.swift:45-47` 直接返回 `response.text`）。真正抛错的是 `OpenAICaller.callAgent`（`AIAPIClient.swift:69-74`）：当响应不是严格的 `choices[0].message` 结构（如 reasoning 模型返回 `content: null` + `reasoning_content`，或网关包了额外字段）时抛 `AIError.parsingFailed`，经 `SparkViewModel.swift:520` 显示为「Agent 执行出错：返回结果解析失败」。
- **标题**：`SparkView.swift:42-58`，标题 `Text(viewModel.currentTitle)` 放在 `ToolbarItem(placement: .topBarLeading)`，被 iOS 26 工具栏挤压截断。
- **发送键**：`SparkInputBar.swift:50-52`，内层 `.background(... accentColor, in: Circle())` + 外层 `.glassIconButton(prominent:)` = 双层。
- **模型配置**：`AIProviderType`（qwenText/doubaoText/deepseek/minimax/qwenVision/doubaoVision/custom）各带 `predefinedModels`（DeepSeek 现仅 `["deepseek-chat"]`）；`AIModelConfiguration{providerType, customEndpoint, customProtocol, modelName, apiKey}`，经 `UserDefaultsAppSettingsStore.loadConfiguration(for:)/saveConfiguration(_:for:)` 按 `.text`/`.vision` 持久化。**`.text` 配置被 Spark 与拍记/照片处理共用**。
- **API 管线**：`OpenAICaller.callAgent/callText`、`AnthropicCaller.callAgent/callText` 当前**不收**任何 reasoning/thinking 参数；payload 在 `callAgent`（`AIAPIClient.swift:39-47`）内构造。
- **Chip 样式**：`SparkAgentChip` 用 `glassSurface(in: RoundedRectangle(cornerRadius: 12), prominent:)` 胶囊，放在 bottom bar `HStack` 内（`SparkView.swift:146-152`）。

## 已确定决策

- **#4 切换范围**：Spark **独立设置**——新增 Spark 专属持久化覆盖 `modelName` 与思考强度；Provider/endpoint/API Key 仍取全局 `.text`，不影响拍记/照片处理。Spark 未设置覆盖时回退全局 `.text.modelName`。
- **#1 修复力度**：新增**确定性日期工具**，让 Agent 调用而非心算；同时修「解析失败」。
- **#2 标题**：移到**内容区自定义 header**（靠左、单行不截断、beta/spinner 在右），移除工具栏 leading 标题项；右上角两个玻璃按钮保留。

---

## 设计

### A. 日期工具 + Agent 解析健壮性（#1）

**A1. `DateInfoTool`** — `Notiee/Features/Spark/Agent/Tools/DateInfoTool.swift`
- 遵循现有 `AgentTool` 协议（`name/description/permission/parametersSchema/execute`），`permission = .read`。
- `name = "date_info"`；参数 `date`（string，可为 `today`/`yyyy-MM-dd`/ISO8601/相对表达如 `下周三`、`tomorrow`），`required: ["date"]`。
- 解析复用 `CalendarQueryTool.parseDate(_:)`；相对中文/英文表达（今天/明天/后天/下周X 等）做有限映射，解析不了则 `success=false` 并提示给出明确日期。
- 返回 `success=true`，`message` 含：ISO 日期、星期几（中/英按当前语言）、距今天数（如「2026-06-24 是星期三，3 天后」）；`data = {iso, weekday, offset_days}`。基于 `Calendar(identifier: .gregorian)`，`now` 由工具内 `Date()` 取（与 prompt 注入一致）。
- 注册：`SparkViewModel.makeAgentExecutor()` tools 数组加入；`AgentToolPresentation` 加 `case "date_info"`（icon `calendar`, displayName「查日期」, runningText「正在查日期…」）。
- Prompt（`agentSystemPrompt`）能力清单加「查询日期/星期几」；行为准则加一条：**凡涉及某日期是星期几、或相对日期换算，必须调用 `date_info`，禁止自行心算**。

**A2. callAgent 解析健壮化** — `AIAPIClient.swift` `OpenAICaller.callAgent`（及 `AnthropicCaller.callAgent` 对应处）
- `choices[0].message` 缺失时不再直接 `parsingFailed`：
  - 若 HTTP 非 2xx 已有 `apiError`（保留）。
  - `content` 用 `as? String ?? ""`（已是）；额外兼容 `reasoning_content`：当 `content` 为空但存在文本性 `reasoning_content` 时，文本回退为空字符串即可（不把思考过程当正文），但**不抛错**。
  - 仅当连 `choices`/`message` 都取不到、且 `tool_calls` 也无时，抛带原始响应片段的 `apiError`（便于诊断），而非裸 `parsingFailed`。
- 目的：Agent 模式下"纯文字答案"稳定走 `AgentExecutor.swift:45-47` 的正常返回路径。
- **注**：精确复现以 systematic-debugging 为准——实现时先用真实/构造响应复现，再按本节调整；若复现指向别处，回到 spec 修订。

### B. 标题自定义 header（#2）
- `SparkView`：移除 `ToolbarItem(placement: .topBarLeading)` 整段；保留 `ToolbarItemGroup(.topBarTrailing)` 两按钮与 `.navigationBarTitleDisplayMode(.inline)`。
- `contentView` 顶部插入一行自定义 header：靠左 `Text(viewModel.currentTitle).font(.headline.weight(.semibold)).lineLimit(1)`，右侧条件显示 beta 徽标（`messages.isEmpty`）或 `ProgressView`（`isGeneratingTitle`）。空会话与有会话两态都显示该 header（贴安全区，水平 padding 与气泡对齐）。

### C. 发送键单层实心玻璃（#3）
- `SparkInputBar.swift`：去掉外层 `.glassIconButton(prominent:)`，保留单个圆形：用 `glassSurface`/`.glassEffect` 给单一 `Circle` 着色（accent / 空输入降饱和 `systemGray4`），内部图标 `arrow.up`（普通）/`stop.fill`（loading）。`.disabled(isEmpty && !isLoading)` 与点击 `isLoading ? onStop() : onSubmit()` 逻辑不变。最终单层实心玻璃圆。

### D. 模型 + 思考强度切换（#4，Spark 独立）

**D1. 数据/持久化**
- `UDK` 加 `sparkModelOverride = "spark_model_override"`、`sparkThinkingLevel = "spark_thinking_level"`。
- 新增 `SparkModelPreferences`（`@MainActor`，读写上述 key），或在 `SparkViewModel` 内聚合：`effectiveModelName`（override 非空则用之，否则全局 `.text.modelName`）、`thinkingLevel`。

**D2. 预设模型列表刷新**（WebFetch 各家官方文档于实现期落实；本设计据 2026-06 研究给出目标值）
- DeepSeek：`deepseek-v4-pro`、`deepseek-v4-flash`（旧 `deepseek-chat`/`deepseek-reasoner` 2026-07-24 弃用，保留为兼容项可选）。
- Qwen(text)：`qwen3.5-plus`、`qwen-plus`、`qwen-max`、`qwen-turbo`。
- Doubao(text)：`doubao-seed-2-0-pro`、`doubao-seed-2-0-lite`、`doubao-seed-2-0-mini`。
- MiniMax：`MiniMax-M3`、`MiniMax-M2.7`。
- 实现期对每家 WebFetch 校正确切 model id 与可用性，再定稿。

**D3. 思考强度（per-provider 能力描述符）** — 新增 `ThinkingCapability`（按 `AIProviderType` 给出）：
- `levels: [ThinkingLevel]`（含 vendor 文档命名 + 文案）与 `apply(to payload:level:)` 注入逻辑：
  - **Doubao**：`reasoning_effort ∈ {minimal, low, medium, high}`。
  - **Qwen**：`enable_thinking: Bool` + `thinking_budget: Int`（强度→budget 档位；含「关闭思考」项）。
  - **DeepSeek**：思考为模型/模式区分（V4 thinking）；以「思考开/关」体现（开→走 thinking 模式/对应 model），不暴露多档 effort。
  - **MiniMax / custom(OpenAI 兼容)**：`reasoning_effort`（minimal/low/medium/high）。
  - 不支持思考的 provider/模型：`levels` 为空 → UI 隐藏该控件。
- 实现期 WebFetch 校正各家参数名/取值与命名。

**D4. API 管线接思考参数**
- `OpenAICaller.callAgent/callText`（必要时 Anthropic 对应）新增可选入参 `reasoning: ReasoningOption?`（含 provider 与 level），在 payload 构造处调用 `ThinkingCapability.apply` 注入。
- `SparkAIService.agentChat/ask` 读取 Spark 的 `effectiveModelName` 与 `thinkingLevel`，传给 caller；模型名用 `effectiveModelName` 覆盖 `textConfig.modelName`。

**D5. UI** — bottom bar `HStack`（agent chip 右侧）
- 「当前模型」胶囊（mirror `SparkAgentChip` 玻璃样式）：显示 `effectiveModelName`，点击弹 `Menu`，列出当前 `providerType.predefinedModels`（custom 则显示已配置 model），选择写入 `sparkModelOverride`。
- 「思考强度」胶囊：仅当当前 provider/model 的 `ThinkingCapability.levels` 非空时显示；点击弹 `Menu` 列各档（vendor 命名），选择写入 `sparkThinkingLevel`。
- 两胶囊在窄屏可省略文字只留图标 + 截断，保证不挤压。

### E. i18n
- 新增用户可见文案三语补全：「查日期 / 正在查日期…」「思考强度」及各档名、模型菜单标题等。zh-Hans 同源、en 英文、zh-Hant 繁体；`plutil -lint` 校验。

## 测试策略
- `DateInfoToolTests`：today/具体日期/相对表达 → 正确星期几与 offset；不可解析 → success=false。
- `ThinkingCapability` 纯函数测试：各 provider `apply(to:level:)` 注入正确键值；不支持的 provider levels 为空。
- Spark 模型覆盖逻辑测试：override 空/非空时 `effectiveModelName` 回退正确。
- callAgent 解析健壮化：构造 `content:null`+`reasoning_content`、缺字段等响应 → 不抛 `parsingFailed`、返回合理 text/toolCalls（可对纯解析函数做单测，必要时抽出可测函数）。
- UI（#2/#3/#4 外观）：iOS 26 build + 肉眼冒烟。
- 全量回归：除既有 `RecordManagerTests.testCapturePhotoStoresRecordAndPersists`（已知失败）外全绿。

## 非目标（YAGNI）
- 不新增 provider（仅刷新现有预设模型列表）。
- 不做 Spark 内编辑 API Key/endpoint（仍在设置页）。
- 不做按会话粒度的模型记忆（Spark 全局一个 override 即可）。
- 不把 vision 模型纳入 Spark 切换。

## 风险/待实现期确认
- 各家 model id 与思考参数随版本变动 → 实现期 WebFetch 逐家校正后再定稿 `predefinedModels` 与 `ThinkingCapability`。
- 「解析失败」精确复现 → 按 systematic-debugging 先复现再改。
- 新增 `.swift` 文件需注册到 target（pbxproj 四处，UUID 全局唯一——见上批 E2 教训）。
