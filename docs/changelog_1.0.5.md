# Notiee 1.0.5 更新日志

> 发布日期：2026 年 6 月 24 日
> （1.0.4 未公开发布，本版本合并 1.0.4 全部内容并新增以下特性）

---

## 纯文字记录

拍记不再局限于拍照——现在你可以直接创建纯文字笔记，随时随地记录想法：

- **手动创建**：在记录库或今日页面点按加号，选择「文字记录」，输入标题和正文即可保存。入口位于 `NewTextRecordSheet`。
- **RecordSource.text**：新增第三种记录来源类型，与拍照（`.photo`）和 Spark 生成（`.spark`）并列，各有专属视觉标识。
  - 拍照记录：显示照片缩略图，详情页包含原图、OCR、AI 摘要全部区域。
  - Spark 生成：显示 sparkles 渐变图标缩略图，无图片预览，仅展示 AI 摘要与内容。
  - 文字记录：显示 doc.text 图标缩略图，无图片预览、无 OCR 区、无 AI 摘要区。
- **零 AI 消耗**：文字记录创建后直接标记为 `completed`，不进入 AI 处理管线，零 token 消耗。
- **详情页自适应**：`RecordDetailViewModel` 根据 `RecordSource` 自动控制各区域可见性——OCR 仅拍照记录显示、摘要区文字记录不显示、Spark 生成的摘要仅在正文不同时展示。
- **向后兼容**：旧版本数据缺少 `source` 字段时默认 `.photo`，升级无感知。

---

## 深度联想 / 相关笔记推荐

记录详情页底部新增智能关联能力，帮你自动发现与当前笔记相关的内容：

### 相关内容推荐

- **语义向量匹配**：打开记录详情时，为该拍记实时计算语义向量（使用 Apple NLEmbedding 端侧引擎，完全离线），与历史记录向量做余弦相似度匹配。
- **独立索引**：使用专用的 `related-notes-index.json` 向量索引文件（位于 `EmbeddingIndex.related`），与搜索索引完全隔离。浏览详情页时**不触发任何云端请求**，隐私绝对安全。
- **高阈值过滤**：匹配阈值设为 **0.6**（高于语义搜索的 0.45），确保推荐质量，最多返回 **3 条**最相关记录。
- **一键跳转**：结果以「🔗 相关内容」Section 在详情页底部展示，每条为 `NavigationLink`，点击直达相关记录详情。

### 续篇笔记检测

- **邻接发现**：同一日程事件下，时间间隔在 48 小时内的相邻拍记自动判定为续篇关系。
- **续篇提示**：当前记录存在"上一篇"时，详情页顶部显示「📎 续篇笔记」链接，方便按时间线回溯。
- **实现位置**：`RecordDetailViewModel.continuationRecord` 计算属性。

### 开关控制

- 实验室新增「深度联想模式」开关（`labDeepAssociationModeEnabled`），默认关闭。
- 关闭后详情页不再计算向量、不展示相关内容 Section，省电省计算。

---

## 日程彩色标签系统

为日程事件引入可定制的彩色标签，在时间轴和拍照时提供直观的视觉区分：

### 系统默认标签（4 个，不可删除）

| 标签 | 颜色 | HEX | 用途场景 |
|------|------|-----|----------|
| 个人 | 蓝 | `#007AFF` | 个人事务、生活日程 |
| 工作 | 橙 | `#FF9500` | 工作会议、项目截止 |
| 课程 | 绿 | `#34C759` | 课程表、上课时间 |
| 临时 | 紫 | `#AF52DE` | 临时安排、不确定事件 |

系统标签使用固定 UUID，跨设备一致性有保障。

### 自定义标签

- **创建入口**：Today 页工具栏 → 标签编辑（`TagEditSheet`），输入名称 + 系统取色器选颜色，一键创建。
- **命名自由**：支持任意中文/英文/emoji 标签名。
- **删除管理**：自定义标签可随时删除，系统标签不可删除。
- **持久化**：标签数据存储在 `Notiee/tags.json`（`EventTagStore`），随 `.tmn` 归档一起备份。

### 标签在 UI 中的呈现

- **日程卡片**：`EventCardView` 在日程卡片左侧显示标签色条 + 标签名称，Today 时间轴一目了然。
- **拍照匹配**：拍照时取景框顶部半透明层显示当前命中日程及其标签色，帮助确认拍摄上下文。
- **ICS 导入**：导入课表/会议文件时，`EventImportPreviewSheet` 支持行内 `Picker` 为每个事件选择标签。

### 技术实现

| 组件 | 文件 | 职责 |
|------|------|------|
| `EventTag` 模型 | `Models/EventTag.swift` (62 行) | 标签实体：`id` / `name` / `colorHex` / `isSystem`，含 `Color(hex:)` 扩展 |
| `EventTagStore` | `Services/EventTagStore.swift` (42 行) | JSON 持久化 + CRUD 操作 |
| `TagEditSheet` | `Features/Today/TagEditSheet.swift` (37 行) | 新建标签表单 UI |
| `EventCardView` | `Components/EventCardView.swift` | 标签色条渲染 |
| `FolderTagManager` | `Services/Managers/FolderTagManager.swift` | 通过 Store 暴露 `customTags` 供全局绑定 |

---

## 法务文件多语种本地化

用户协议与隐私政策全面升级，覆盖 4 个语言变体，按 App 语言与设备地区智能路由：

| App 语言 | 设备地区 | 加载文件 |
|----------|----------|----------|
| 简体中文（zh-Hans） | — | `*_zh-Hans.html` |
| 繁體中文（zh-Hant） | 非 TW | `*_zh-Hant-HK.html`（港澳繁體，私隱政策 / 用戶協議） |
| 繁體中文（zh-Hant） | TW | `*_zh-Hant-TW.html`（台灣繁體，隱私權政策 / 使用者條款） |
| English（en） | — | `*_en.html`（Privacy Policy / Terms of Service） |
| 系统默认 | Locale.current 推断 | 以上规则，无法匹配时回退 `zh-Hans` |

- **格式升级**：从 PDF 切换为 HTML（WKWebView 内嵌），支持明暗模式自适应、动态字号、系统字体（PingFang SC/HK/TC 按语言适配）。
- **内容修订**：
  - 「中国」统一写全称为「中华人民共和国」/ `People's Republic of China`。
  - 移除「我 → 反馈」入口引用（该功能未实现），保留邮箱和开发者网页作为联系方式。
- **路由实现**：`AboutNotieeView.swift` 的 `legalLocaleSuffix` 计算属性 + `LegalHTMLView` 的 `LegalDocument` 枚举。
- **文件清单**：`Notiee/Legal/` 目录内含 8 个 HTML 文件（UserAgreement × 4 + PrivacyPolicy × 4）。

---

## 待办管理强化

- **本地持久化明确化**：所有待办事项（含截止日期 `dueDate`、提醒标记）坚定本地 JSON 存储，无云端依赖。卸载 App 即清除（iCloud 同步的需手动删除）。
- **AllTodosView 细节完善**：待办分桶（`TodoBucketer`）按逾期 / 今天 / 明天 / 本周 / 更晚 / 无截止日期六组展示，已完成待办可折叠，每行显示内容 + 截止日 + 提醒铃 + 关联记录名，支持左滑删除。
- **Today 预览精简**：Today 页只显示当下可执行待办（逾期 + 今天截止 + 无截止），封顶 5 条，底部「查看全部 N 条待办」一键跳转。

---

## 技术细节

| 项目 | 说明 |
|------|------|
| 新增文件 | `NewTextRecordSheet.swift`、`EventTagStore.swift`、`changelog_1.0.5.md`；`Notiee/Legal/` 目录下 6 个新增法务 HTML（zh-Hant-HK / zh-Hant-TW / en 各 2 个） |
| 修改文件 | `NoteRecord.swift`（新增 `RecordSource.text`）、`RecordDetailViewModel.swift`（`continuationRecord`、`relatedRecords`、`RecordSource` 感知区域可见性）、`RecordDetailView.swift`（`relatedNotesSection`、`continuationSection`、非 photo 来源隐藏图片）、`EmbeddingIndex.swift`（新增 `relatedNotes` 静态索引）、`SemanticSearchEngine.swift`（新增 `related()` 方法）、`EventTag.swift`（系统标签 + `Color(hex:)` 扩展）、`EventCardView.swift`（标签色条渲染）、`FolderTagManager.swift`（聚合 `EventTagStore`）、`LabFeaturesView.swift`（新增深度联想开关）、`AboutNotieeView.swift`（法务路由支持 4 语种）、`LegalHTMLView.swift`（新增 `LegalDocument.bundleURL` + `localeSuffix`）、`MeView.swift`（日程管理入口调整）、`docs/legal/*.md`（4 语种法务 MD 源文件） |
| 第三方依赖 | 无变化（仍为 ZIPFoundation, MarkdownUI, OnboardingKit, WhatsNewKit, lottie-ios, NetworkImage, swift-cmark, PageView） |
| 系统权限 | 无新增 |
| 向后兼容 | `RecordSource` 缺失字段默认 `.photo`；深度学习索引独立于搜索索引，不存在时自动重建；旧版法务 PDF 完全替换为 HTML，不影响现有功能 |

---

## 已知限制

- **深度联想**目前仅对拍照记录（`.photo`）计算相关推荐，文字记录和 Spark 生成暂不支持。
- **日程标签**每个日程仅支持绑定一个标签，暂不支持多标签。
- **法务文件**浏览器历史记录在 WKWebView 中不可用，用户无法在法务页面内使用前进/后退导航。

---

> **版本历史**
> - **v1.0.5**（2026-06-24）：纯文字记录、深度联想 / 相关笔记推荐、日程彩色标签、法务多语种本地化、待办持久化明确
> - v1.0.4（2026-06-24，未公开发布）：本地账户系统、Spark Agent 工具扩展（WebFetch / DateInfo / ScheduleUpdate）、RAG 语义检索、全量待办管理、记录来源区分（photo/spark）、iOS 26 Liquid Glass 适配、模型与思考切换器、Spark 对话体验优化
> - v1.0.3（2026-06-04）：Spark AI 助手、Agent 模式、多语言适配
> - v1.0.1：初始版本
