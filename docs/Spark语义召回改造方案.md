# Spark 普通问答 · 语义召回改造方案

> 状态：**方案评估（未落地）** · 2026-07-21
> 目标：解决 Spark 普通问答（非 Agent）的「150 条硬天花板」与「每轮全量倾倒 token」两个结构性问题。

---

## 1. 为什么要改（问题定义）

当前 `SparkAIService.ask()` → `buildSystemPrompt()` 的召回逻辑：

- 取 **最近 150 条**记录（`maxRecordsInPrompt = 150`），纯按 `capturedAt` 倒序截断，**零相关性排序**。
- 每条只塞 **标题 + 摘要（截断 100 字）**，放进 system prompt 的「当前拍记」块。
- `[来源N]` 的 N = 记录在这个列表里的 **1-based 位置**。

两个结构性问题：

1. **150 条硬天花板**：用户第 151 条之后的老记录，Spark **永远看不到**。「我去年三月那个会议记了啥」答不出来——不是没找到，是压根没进 prompt。
2. **每轮全量倾倒**：不论用户问的是不是笔记，每轮都注入 ≈150 × 115 字 ≈ **1 万+ token**。重度用户 + 免费版后端按 token 记账 = **成本失控**（用户担心的「Spark 变大流量入口」）。

> 注：语义引擎其实**已经存在且在跑**——只是只接在 **Agent 的 `note_search` 工具**和**详情页「相关内容」**里。普通问答完全没用上。

---

## 2. 方案选型：分层混合（不是全量替换）

「普通问答全量切语义」会解决问题 1，但**引入新回归**：「我最近记了啥」「帮我梳理这周」这类**浏览 / 时序查询**要的是近期列表，不是语义匹配。

**采用分层混合**：

```
prompt 记录块 =  近期锚点层（top ~15，标题+摘要）      ← 保浏览 / 时序查询
              +  语义召回层（top K，注入全文）          ← 破 150 天花板 + 深度问答
              （两层去重合并，语义层排除已在锚点层的）
```

对照两个动机：

| 痛点 | 分层混合怎么解 |
|---|---|
| 超过 150 条老记录丢失 | 语义层可召回**任意时间**的老记录，无硬天花板 |
| Spark 变大流量入口 | 记录块从 ≈1 万 token 降到 ≈3K（15 摘要 + K 全文），**反而更省** |
| （额外收益） | 语义层注入**全文**而非仅摘要，深度问答质量上升 |

**免费档向量**：分层混合下，语义只是**补充层**，近期锚点层保底。所以**免费档先用本地 `NLEmbedding` 即可**——最坏情况只是「老记录偶尔没捞准」，近期查询完全不受影响。等要给免费档更好体验时，打开后端 `/ai/embed` 是平滑升级，不阻塞本次。

---

## 3. 参数（初始值，可调）

| 参数 | 初值 | 说明 |
|---|---|---|
| 近期锚点条数 | 15 | 标题+摘要，保时序 / 浏览 |
| 语义召回 K | 8 | 注入全文（`RecordEmbeddingText.compose`，≤2000 字/条） |
| 语义阈值 | 0.45 | 复用 `SemanticRanker` 默认，低于此不召回 |
| 全文单条上限 | ~800 字 | 防单条长笔记吃穿 token；比锚点的 100 字摘要深，但有界 |
| 合并后总条数上限 | ~20 | 去重后硬顶，控 token |

---

## 4. 落地改动点（引擎全现成，改的是接线）

所有改动在 `SparkAIService`（共享文件，**两个 Target 同时生效**）。`BackendSparkAIService` 复用同一个 `buildSystemPrompt`，自动跟随。

### 4.1 `ask()` — 注入语义召回
- 现：`activeRecords = allRecords.filter{!isDeleted}.sorted.prefix(150)`
- 改：
  1. `anchors = sorted.prefix(15)`（近期锚点）
  2. `semantic = await SemanticSearchEngine.search(query: question, in: 候选, limit: K)`
     - 候选 = 全部未删除未加密记录（不再 prefix 150）
  3. `merged = anchors + (semantic 去掉已在 anchors 的)`，`[来源N]` 按 merged 顺序编号
- `SparkAIService` 需持有 / 懒建一个 `SemanticSearchEngine`（参照 `SparkViewModel.makeAgentExecutor()` 的装配：Hybrid(local, cloud) + `EmbeddingIndex.live`）。

### 4.2 `buildSystemPrompt()` — 记录块分层
- 锚点层：维持现状（标题 + 摘要 100 字）。
- 语义层：新增块，注入**全文截断**（~800 字），标注为「语义相关的历史记录」。
- 保持 `[记录N]` 连续编号（锚点在前、语义在后），**N 与 merged 数组下标严格对齐**。

### 4.3 `[来源N]` 引用映射 — ⚠️ 最高风险点
- 现在引用强依赖「记录在列表里的固定位置」，且 `SparkViewModel.processQuestion` 里 `extractCitations(recordCount: all.count)` 把 N-1 映射进 **`all`（全量 sorted）**——之所以现在能对，是因为 `records` 是 `all` 的前缀、同序。
- **分层混合后 merged 不再是 all 的前缀**（含跳跃的老记录），这个隐含耦合会**断裂**。
- 必须改成：`ask()` 把「merged 记录列表」显式传出，引用按 **merged 的实际 record.id** 映射，不再靠位置猜。`SparkViewModel` 的 `extractCitations` / `Citation` 构造要跟着改成消费这个显式列表。
- **这块是本次改造的测试重心**——引用错位会让用户看到「[来源2]」点开却是别的记录。

### 4.4 冷启动回填
- 首次进 Spark 时触发 `SemanticSearchEngine.backfill(records:)` 给存量记录补向量。
- 免费档本地 `NLEmbedding` = **零成本零延迟**，可直接后台跑。
- 云端向量（若启用）= N 次 API 调用，需限速 / 分批 / 仅增量。

---

## 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| `[来源N]` 引用错位（§4.3） | 改为按 record.id 显式映射；重点单测 + 手测 |
| 语义每轮加一次 embedding 延迟 | 本地向量 <10ms；查询向量单条，锚点层先行可先渲染 |
| 本地中文向量质量一般 | 分层保底（锚点层不依赖向量）；关键词加权（`SemanticRanker` 已有）兜关键词命中 |
| 纯闲聊也跑语义 = 浪费 | 可选 §6 查询路由；或先无脑跑（本地零成本，问题不大） |
| 首次回填给大量老记录算向量 | 本地零成本；云端需增量 + 限速 |

---

## 6. 可选增强（本次可不做）

- **查询路由**：纯闲聊（`SparkIntentDetector` 可复用）跳过语义层，只留锚点，进一步省。
- **免费档云端向量**：后端 `/ai/embed` 对免费档开放（当前设计是 Pro-only / `localOnly`）——商业 / 成本决策，需配额 + 防刷。留作后续升级口。

---

## 7. Target 归属

- **核心改动全在共享代码**（`SparkAIService.ask` / `buildSystemPrompt` / 引用映射）→ **两个 Target 都生效**。
- **分叉点仅在 embedding 来源**：
  - Notiee+（BYOK）：可用云端向量（复用用户自己的 key），质量最好。
  - 免费版：先本地 `NLEmbedding`；后端 `/ai/embed` 是否给免费档 = 后续商业决策。
- 无需新增 `#if NOTIEE_PLUS` 分叉——来源差异已被 `HybridEmbeddingService` 的 `preferCloud` 开关吸收。

---

## 8. 落地顺序建议

1. `SemanticSearchEngine` 接入 `SparkAIService`（装配 + 懒建）。
2. `ask()` 分层合并 + merged 列表显式传出。
3. `buildSystemPrompt()` 记录块分层。
4. **`[来源N]` 改按 record.id 映射**（+ 单测）。
5. 冷启动 `backfill` 触发。
6. 手测四类查询：近期浏览 / 时序梳理 / 老记录深挖（>150 条外）/ 纯闲聊；重点验引用不错位。
