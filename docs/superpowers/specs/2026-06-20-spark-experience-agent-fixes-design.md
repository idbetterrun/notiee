# Spark 体验与 Agent 修复 — 设计方案

| 字段 | 值 |
|------|-----|
| 文档版本 | 1.0 |
| 创建日期 | 2026-06-20 |
| 所属产品 | Notiee |
| 涉及模块 | Spark（AI 伴侣 / Agent 模式） |
| 分支 | feature/ai-agent |

---

## 一、背景与目标

Spark 是 Notiee 内的个人 AI 伴侣，近期新增了 Agent 模式（工具调用 / 自主执行）。
真机使用中暴露出一批体验与正确性问题。本方案针对以下 7 项缺陷/需求给出统一解决方案：

1. Agent 模式有 bug（calendar_query 报错、能力缺口），且工作时的视觉呈现过于粗暴。
2. Agent 模式开关位置不佳，需重做为浮于输入框左上方的圆角矩形 chip + SF Symbol 图标。
3. Markdown 渲染失败（表格、分隔线渲染错误）。
4. 英文提问却得到中文回复（仅 Agent 模式）。
5. 回复时偶发整个 App 卡死。
6. 新增预测能力：非 Agent 模式下若用户意图为「干活」，回复后提示切换 Agent。
7. 对话自动命名逻辑产出的标题质量差。

---

## 二、根因诊断（已定位）

| 问题 | 根因 | 位置 |
|------|------|------|
| Markdown 渲染失败 | 手写 `MarkdownParser` 不支持表格、不支持分隔线 `---`（`---` 被 `hasPrefix("-")` 误判为列表项 `--`）。项目已依赖 `swift-markdown-ui` 但 Spark 未使用 | `SparkChatBubble.swift:29-79`、`:60` |
| 英文进中文出 | 普通问答 prompt 有严格语言匹配规则，但 Agent 模式 prompt 整段中文、无语言规则；收尾总结句也硬编码中文 | `SparkAIService.swift:491-498`（有规则）、`AgentExecutor.swift:155-177`、`:72`（缺规则） |
| calendar_query 报错 | LLM 对「明天」传 `time_range=custom` + 纯日期串（如 `2026-06-21`），`ISO8601DateFormatter` 解析失败 → 抛 `AgentToolError.missingParameter`（即「错误 0」）→ 原始枚举错误裸奔给用户 | `CalendarQueryTool.swift:44`、`NoteSearchTool.swift:82` |
| Agent 无法创建日程 | 工具集中无「创建日程」工具，能力缺口。但 `CalendarManager.addEvent()` 已存在 | `SparkViewModel.swift:429-439`、`CalendarManager.swift:215` |
| Agent 呈现粗暴 | 仅一行「Agent 正在执行: xxx…」+ 几条裸 tool message（含中文报错原文） | `SparkView.swift:235-261` |
| Agent 开关位置 | 现为右上角 header 小胶囊 | `SparkView.swift:147-157` |
| 卡死 | 首要嫌疑：手写 markdown 在主线程重解析长文本 + `Text` 深层拼接 + 全局 `markdownCache` 无上限增长。次要嫌疑：`AgentExecutor` 整体 `@MainActor`，工具循环 + JSON 序列化占用主线程 | `SparkChatBubble.swift:12-13,162-274`、`AgentExecutor.swift:3` |
| 对话命名差 | 命名 prompt 纯中文（英文对话出中文名）、限死 10 字、裸裁首句前 15 字当临时标题、需满 3 轮才触发 | `SparkViewModel.swift:294-344` |

---

## 三、设计方案（7 个工作流）

### 工作流 1 — Markdown 渲染重做（修问题 3，缓解卡死）

- 移除 `SparkChatBubble.swift` 中的手写 `MarkdownParser`、`renderLine`、`renderInlines`、全局 `markdownCache` / `markdownCacheLock` / 4 个全局 `NSRegularExpression`。
- 改用已依赖的 **`swift-markdown-ui`（MarkdownUI）** 渲染助手消息正文。
- 编写自定义 `Theme`，使渲染结果在字号、行距、引用条、代码块、列表符号上与当前气泡视觉保持一致。
- `[来源N]` 引用：在交给 MarkdownUI 前由现有 `extractCitations` / `extractCitationsFallback` 抽取（逻辑不变）；正文中 `[来源N]` 作为普通文本展示；底部 citations 区照旧。
- 用户气泡保持纯 `Text`（不走 markdown）。
- **附带收益**：删除手写 parser 即移除卡死首要嫌疑（主线程重解析 + Text 深层拼接 + 无上限缓存）。

**验收**：表格、分隔线 `---`、嵌套列表、粗/斜体、行内代码、代码块均正确渲染；`[来源N]` 仍显示且可点击跳转。

### 工作流 2 — Agent 语言匹配（修问题 4）

- 将 `SparkAIService` 中的语言匹配规则（当前在 `buildSystemPrompt` 内联，约 491-498 行）提取为一个共享字符串常量（如 `SparkPromptFragments.languageRule`）。
- 在 `AgentExecutor.buildAgentSystemPrompt` 注入该规则。
- 将 `AgentExecutor.swift:72` 的收尾总结句由硬编码中文改为「请用与用户相同的语言总结你完成了哪些操作」。

**验收**：Agent 模式下英文提问得到全英文回复；中文提问得到中文回复。

### 工作流 3 — Agent 开关重做（修问题 2）

- 从 `SparkView.headerView` 移除 Agent 胶囊（保留新建对话、历史两个按钮）。
- 在 `SparkInputBar` 正上方左侧浮一个**圆角矩形 chip**：`Image(systemName:)` 图标 + 「Agent」文字。
- 两态：开启 = 主题色实心 + 白字；关闭 = 描边/灰。
- 图标默认 `bolt.fill`（可由用户后续替换为 `wand.and.rays` 等）。
- 绑定 `viewModel.isAgentModeEnabled`，点击切换。

**验收**：chip 浮于输入框左上方，开关两态视觉清晰，图标在文字前。

### 工作流 4 — Agent 工作呈现：可折叠步骤时间线（修问题 1）

- 替换 `SparkView.swift:235-261` 的裸状态行与裸 action 列表。
- **工作中**：一条活的状态行 = 工具图标 + 友好文案（如「正在查日程…」「正在创建拍记…」），文案按 `toolName` 查本地化映射表。
- **完成后**：折叠为「执行了 N 步」时间线卡片，可展开查看每步：工具图标 / 友好名 / ✓✗ 状态 / 详情。
- 新增工具元数据：为每个 `AgentTool` 提供 `displayName`（本地化）与 `iconName`（SF Symbol），或集中维护一张 `toolName → (icon, displayName)` 映射表（避免改动每个工具文件，倾向集中映射表）。
- **错误不再裸奔**：`AgentToolError` 实现 `LocalizedError`，时间线展示友好文案而非「错误 0」。

**验收**：Agent 工作过程有清晰的图标 + 友好文案；完成后可折叠/展开；失败步骤显示可读的错误说明。

### 工作流 5 — Agent bug 修复 + 能力补全（修问题 1）

- **calendar_query 加固**（`CalendarQueryTool.swift`）：
  - 支持相对日期：`tomorrow` / `day_after_tomorrow`（或在 time_range 枚举中扩展，并/或在 custom 解析里识别）。
  - 放宽日期解析：除 ISO8601 外，接受 `yyyy-MM-dd`。
  - `custom` 缺日期时降级为合理默认（如今天）而非抛错。
- **新增 `ScheduleCreateTool`**（`permission = .write`）：
  - 参数：title、start_date、end_date（可选）、all_day（可选）。
  - 实现：构造 `ScheduledEvent` 调 `CalendarManager.addEvent()` 写入应用日程。
  - 提供 `undoAction`（删除刚创建的事件）。
  - 注册进 `SparkViewModel.makeAgentExecutor()` 工具集。
- **清理魔法字符串**：移除 `AgentExecutor.swift:106` 残留的 `result.data?["stop_agent"]`，统一走 `AgentToolResult` 的终止语义 / `shouldTerminate` 字段。
- **卡死次要嫌疑加固**：将工具执行循环中的 JSON 序列化与可阻塞工作移离主线程（在保持状态更新于 `@MainActor` 的前提下）。

**验收**：「看明天的日程」不再报错；「创建一个日程」可成功写入并在 Today/日程中可见且可撤销。

### 工作流 6 — 预测式 Agent 建议（新功能，问题 6）

- 新增本地意图启发式（如 `SparkIntentDetector.looksLikeActionRequest(_:) -> Bool`）：一组动作动词正则（创建/帮我/提醒/安排/记一下/create/remind/schedule/add…）。
- 非 Agent 模式下，普通问答回复完成后，若用户原始消息命中启发式 → 在该条助手消息**下方**渲染一个「⚡ 用 Agent 模式重试」快捷 chip。
- 点击：`isAgentModeEnabled = true` + 用该用户消息重新走 `runAgent()`。
- 该提示为 per-message 状态，不污染历史持久化（或持久化但不影响加载行为）。

**验收**：非 Agent 模式下输入「帮我创建一个明天的日程」，回复下方出现切换 chip；点击后自动开 Agent 并重跑。

### 工作流 7 — 对话命名重做（问题 7）

- 触发时机：首轮问答（1 轮）完成后即生成上下文标题，不再等满 3 轮。
- 命名 prompt 改为**语言匹配**：英文对话出英文标题。
- 长度放宽到 ≤20 字符（含英文）。
- 临时标题更克制：避免裸裁首句前 15 字产生碎片；命名失败兜底同样走语言匹配。
- 保留 `containsModelName` 过滤（避免标题里出现模型名）。

**验收**：英文对话得到合理英文标题；中文对话得到简洁中文标题；标题不再出现奇怪碎片。

---

## 四、卡死问题（问题 5）处理策略

- 工作流 1 已移除首要嫌疑（手写 markdown 主线程解析 / Text 深层拼接 / 无上限缓存）。
- 工作流 5 加固次要嫌疑（`AgentExecutor` 主线程占用）。
- **真正确认需用户复现并提供 Xcode 日志**（场景、Agent/普通模式、回复长度）。在拿到日志前，本方案对卡死按「加固」处理，不声称「已修复」。待日志到位后按 systematic-debugging 流程定位确认。

---

## 五、影响文件清单

| 文件 | 变更类型 | 工作流 |
|------|----------|--------|
| `SparkChatBubble.swift` | 重写渲染（移除手写 parser，接入 MarkdownUI） | 1 |
| `SparkAIService.swift` | 提取语言规则常量；命名 prompt 重做 | 2、7 |
| `AgentExecutor.swift` | 注入语言规则；收尾句语言匹配；移除 stop_agent 魔法字符串；主线程加固 | 2、5 |
| `SparkView.swift` | 移除 header 胶囊；接入浮动 chip 与时间线呈现 | 3、4 |
| `SparkInputBar.swift`（或新增 chip 视图） | 浮动 Agent chip | 3 |
| 新增 Agent 时间线视图 | Agent 工作呈现 | 4 |
| `AgentToolProtocol.swift` / 工具映射表 | 工具 icon/displayName 元数据 | 4 |
| `NoteSearchTool.swift`（AgentToolError） | `LocalizedError` 实现 | 4 |
| `CalendarQueryTool.swift` | 相对日期 + 宽松解析 + 降级 | 5 |
| 新增 `ScheduleCreateTool.swift` | 创建日程工具 | 5 |
| `SparkViewModel.swift` | 注册新工具；意图检测；切换 chip 行为；命名逻辑重做 | 5、6、7 |
| 新增 `SparkIntentDetector` | 本地意图启发式 | 6 |
| i18n（en/zh-Hans/zh-Hant） | 新增文案本地化 | 3、4、6 |

---

## 六、非目标（Out of Scope）

- 不改动普通问答（非 Agent）的 prompt 主体逻辑，仅提取语言规则常量复用。
- 不接入系统 EventKit 写入（ScheduleCreateTool 写入应用自有日程存储，规避权限复杂度）。
- 不做 Agent 流式输出（streaming）。
- 不在本方案内重构 `AgentExecutor` 的整体并发模型（仅做必要的主线程加固）。
