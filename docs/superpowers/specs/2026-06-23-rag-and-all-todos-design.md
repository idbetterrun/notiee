# 设计文档：RAG 语义检索 + 「所有待办」入口

- 日期：2026-06-23
- 范围：两个相互独立的特性，合并为一份方案
  - Part A：为 Spark Agent 的 `note_search` 工具加入混合语义检索（RAG）
  - Part B：在「我」页新增「所有待办」完整管理入口，Today 保持精简
- 状态：已与用户确认设计方向，待评审

---

## 背景与动机

当前两处明确痛点：

1. **拍记搜索是纯子串匹配。** `NoteSearchTool` 仅用 `localizedCaseInsensitiveContains` 在 `title / summary / ocrText` 上做关键词匹配（见 `Notiee/Features/Spark/Agent/Tools/NoteSearchTool.swift:38`）。因此「搜机器学习」无法命中写着「深度学习 / AI」的拍记 —— 这正是用户截图里的失败场景。

2. **待办没有统一的全量管理入口。** Today 的待办区块定位为「当下概览」，且历史/已完成无处可看。`MeView`（我）已有「全部日程 → `AllSchedulesView`」的成熟范式，待办缺少对应的「所有待办」。

### 已确认的关键决策

- **Embedding 来源：混合（本地为主 + 云端可选）。** 默认端上计算，保隐私、可离线；设置中提供「高质量云端检索」开关。
- **待办入口定位：Today 保持精简，全量看「所有待办」。** Today 只显示「当下可执行」的少量待办作为概览；完整管理（分组、增删改、已完成历史）在新页面。
- **RAG 覆盖面：仅 Spark Agent 的拍记搜索（起步）。** 只升级 `note_search`，记录页手动搜索框暂不纳入本期。

---

## Part A：混合语义检索（RAG）

### 目标

让 `note_search` 在保留关键词命中的前提下，增加语义排序，修复「语义相关但字面不同」检索不到的问题。**关键词命中作为下限保底**，确保不回退现有行为；同时设相关度阈值，避免无关结果污染。

### 组件划分（4 个新组件 + 1 个改造工具）

#### 1. `EmbeddingService` 协议与实现

```
protocol EmbeddingService {
    /// 返回归一化向量；无法计算时抛错（由上层降级处理）
    func embed(_ text: String) async throws -> [Float]
    /// 模型标识（写入索引用于失效判断），如 "nlembedding-zh-v1" / "cloud-<model>"
    var modelIdentifier: String { get }
}
```

实现：

- **`LocalEmbeddingService`（默认，离线，端上）**
  - 起步用 Apple `NLEmbedding`；中文句向量质量不足时降级到关键词保底（见「降级链」）。
  - 预留：后续可替换为内置小型 CoreML 多语言模型（如 MiniLM，约 100MB 包体）以提升中文质量，协议不变。
- **`CloudEmbeddingService`（可选，云端）**
  - 调用用户已配置的 AI 服务商 embedding 接口，仅当「高质量云端检索」开关开启时启用。
- **`HybridEmbeddingService`（对外入口）**
  - 依据设置开关 + 网络状态选择底层实现。
  - **降级链：云端 → 本地 → 关键词保底。** 任一层失败自动降级，`note_search` 永不因检索失败而整体报错。

#### 2. `EmbeddingIndex`（向量旁路存储）

- 持久化结构：`[UUID: Entry]`，`Entry = { vector: [Float], model: String, contentHash: String }`。
- **独立于 `NoteRecord` JSON**（旁路 sidecar 文件），原因：
  - 不污染、不破坏现有 record 持久化格式（无需迁移）。
  - 可独立重算、独立失效。
- `contentHash`：对参与 embedding 的文本求哈希，编辑拍记后用于判定旧向量是否过期。
- `model`：记录产出该向量的模型标识；模型变更时整体视为过期。

#### 3. 索引生命周期

- **写入时索引**：拍记创建/更新（AI 处理产出 `title/summary/ocrText` 之后），对 `title + summary + ocrText`（截断到合理长度）计算 embedding，写入 `EmbeddingIndex`（含 `contentHash`）。
- **启动时回填**：App 启动后台任务，为缺失/过期向量的存量拍记补算（个人规模数百条，可后台分批）。
- **搜索时兜底**：检索时若仍有缺失/过期项，按需即时补算并缓存。

#### 4. `SemanticRanker`

- 暴力余弦相似度（个人规模数百条，无需向量数据库）。
- **混合打分策略**：
  1. 关键词命中（现有子串匹配）的拍记**始终纳入**结果（保底，不回退）。
  2. 语义部分取 query 向量与各拍记向量的余弦相似度，保留**高于相关度阈值**的 top-k。
  3. 合并去重后按综合分排序，截断到 `limit`。
- 阈值作用：无语义相关项时（如「量子计算」且确无相关笔记）返回空，而非塞入弱相关噪声。

#### 5. `NoteSearchTool` 改造

- 注入可选 `EmbeddingService` 依赖（`SparkViewModel.makeAgentExecutor()` 装配）。
- **输出数据结构不变**（`record_id / title / summary / ...`），保证 Agent 后续工具链不受影响。
- 无 embedding 能力（如离线且本地引擎不可用）时，退化为纯关键词（当前行为）。

### 设置项

- 在 AI / 实验室设置中新增「高质量云端检索」开关（默认关闭，即默认端上）。

### 失败与降级

- 离线 + 选了云端 → 降级本地；本地不可用 → 关键词保底。
- 任意一步失败都不让整个 `note_search` 报错，对 Agent 始终返回可用结果。

### 测试策略

- `SemanticRanker`：用合成向量做确定性单测（已知夹角 → 已知排序）。
- 混合合并：验证关键词命中项必定保留；验证阈值能挡掉无关项。
- 降级：mock `EmbeddingService` 抛错，验证退化为关键词且不抛出。
- `EmbeddingIndex`：`contentHash` 变化 → 判定过期；持久化往返。

---

## Part B：「所有待办」完整管理页

### 目标

提供统一的全量待办管理入口；Today 保持精简，仅作「当下可执行」概览。基于已修复的待办过滤 bug（独立待办 `recordID == nil` 现已能在 Today 显示）继续构建。

### 入口

- `MeView`（我）在「全部日程」同一区块新增：

```
NavigationLink { AllTodosView(store: store) } label: {
    Label("所有待办", systemImage: "checklist")
}
```

  仿照现有 `AllSchedulesView` 范式。

### `AllTodosView` 设计

- **未完成**：按截止日期分桶分组，逾期优先：
  `已逾期 / 今天 / 明天 / 本周 / 更晚 / 无截止日期`。
- **已完成**：可折叠分区，按完成时间倒序 —— 这是 Today 不再承载的「历史」面。
- **行（Row）**：
  - 勾选框切换完成（`store.toggleTodo`）。
  - 内容、截止日期、提醒铃铛图标。
  - 若来自某条拍记，显示来源拍记标题，点击跳转该拍记详情。
  - 点击整行 → 复用现有 `TodoDetailSheetView` 编辑。
  - 左滑删除（`store.deleteTodo`）。
- **新增**：工具栏 `+`，复用现有 `CreateItemSheet`（`.todo` 分支）→ `store.addStandaloneTodo`。

### Today 改动（保持精简）

- 现有「待办事项」区块保留，但定位为**当下概览**：
  - 仅显示「可执行」的待办：逾期 / 今天到期 / 无截止日期；隐藏远期与已完成。
  - 数量封顶（如 5 条）。
  - 底部增加「全部待办 →」链接跳转 `AllTodosView`。

### 复用与依赖

- 无需新增 store 方法：`addStandaloneTodo / deleteTodo / toggleTodo / updateTodoContent` 均已存在。
- 复用 `TodoDetailSheetView`、`CreateItemSheet`。

### 测试策略

- 分桶逻辑单测：给定混合截止日期 → 正确落入 `已逾期/今天/明天/本周/更晚/无截止`。
- Today 概览过滤单测：远期与已完成不出现；逾期/今天/无截止出现；封顶生效。
- 已完成分区排序（倒序）。

---

## 范围之外（本期不做）

- 记录页手动搜索框接入语义检索（RAG 起步仅覆盖 Agent）。
- 内置 CoreML 多语言 embedding 模型（作为后续质量升级，协议已预留）。
- 待办的提醒/通知调度改造（沿用现有 `hasReminder` 语义）。

## 风险与权衡

- **本地中文 embedding 质量**：`NLEmbedding` 中文句向量质量有限，靠「关键词保底 + 云端可选」兜住；CoreML 小模型作为后续升级路径。
- **回填性能**：存量拍记后台分批补算；搜索时按需兜底，避免首搜卡顿。
- **包体**：起步用 `NLEmbedding` 零包体；CoreML 模型（约 100MB）留待评估再引入。
