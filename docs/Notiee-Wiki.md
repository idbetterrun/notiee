# Notiee Wiki

> **Notiee** — 用相机来记、用问话来找的私人记忆库
> 一款 iOS 原生 SwiftUI 应用：看到想记的东西，举起相机拍下就好，不用当场整理。
> Notiee 自动认出照片里的文字、理成清爽的笔记；真正的价值在以后——这些内容你都能搜到，
> 也能直接开口问，从自己拍过的东西里得到答案，并溯源回原始那张照片。

| 项目 | 信息 |
|---|---|
| 平台 | iOS 18.0+ |
| 语言 | Swift 6.0+ |
| 构建 | Xcode 16.0+ |
| 架构 | SwiftUI + MVVM + 中心化 Store/Manager 组合 |
| 数据 | 离线优先（本地 JSON / UserDefaults / Keychain） |
| 版本 | 当前 main（含 Notti AI 助手、加密记忆、Agent 工具与语义检索；双版本 Notiee / Notiee+） |
| 许可 | Proprietary |

---

## 目录

1. [产品定位](#1-产品定位) · [1.1 两个版本（Notiee / Notiee+）](#11-两个版本notiee--notiee)
2. [核心概念](#2-核心概念)
3. [应用结构（四大模块）](#3-应用结构四大模块)
4. [记录来源（RecordSource）](#4-记录来源recordsource)
5. [本地账户系统](#5-本地账户系统)
6. [Notti AI 助手与 Agent](#6-notti-ai-助手与-agent)
7. [语义检索引擎 / RAG](#7-语义检索引擎--rag)
8. [深度联想 / 相关笔记推荐](#8-深度联想--相关笔记推荐)
9. [AI 处理流水线](#9-ai-处理流水线)
10. [数据模型](#10-数据模型)
11. [状态管理与架构](#11-状态管理与架构)
12. [技术栈与依赖](#12-技术栈与依赖)
13. [iOS 26 Liquid Glass 适配](#13-ios-26-liquid-glass-适配)
14. [日历日程标签系统](#14-日历日程标签系统)
15. [目录结构](#15-目录结构)
16. [备份与同步](#16-备份与同步)
17. [权限与隐私](#17-权限与隐私)
18. [本地化](#18-本地化)
19. [构建与测试](#19-构建与测试)

---

## 1. 产品定位

**一句话**：用相机来记、用问话来找的私人记忆库。看到就拍，需要时再回来找它，或者直接问它。

**核心痛点**：过去拍进系统相册的照片——白板、一页书、会议纪要、单据、街上一段话——往往就此
石沉大海：想不起拍过、也搜不出来，等于扔进黑洞。问题不在"拍"，而在"以后用不上"。

**产品思路（检索优先）**：Notiee 把价值重心从"拍的那一刻"移到"回头找的那一刻"。
- **拍照只是最省事的输入**：物理世界的信息（纸、屏幕、白板）不用打字，拍一下就进库。
- **拍完自动理成笔记**：后台异步队列调用大模型做 OCR（含 LaTeX）、生成一句摘要 + 要点 + 待办，
  你不用当场整理，拍完就走。
- **落点在检索端**：既能穿透全文搜索（标题 / 摘要 / OCR 原文、命中词高亮），也能直接问 **Notti**——
  从你自己拍过的内容里给出答案，并附上出处、可跳回原图。这是 Notiee 与"随手拍进相册"之间真正的鸿沟。
- **离线优先**：无网时本地缓存秒开，网络恢复后自动续跑 AI 处理。

**顺带的能力（不再作为主定位）**：
- **日程锚点**：拍照瞬间自动挂到当前日程/场景，作为回头查找的时间线索，而非核心卖点。
- **场景增强**：针对具体使用场景（如学生课堂）可开启知识点提炼、名词解释、LaTeX 等增强，属加分项。

**目标人群**：不设人群门槛——任何人、任何时候，有个懒得打字的视觉信息，拍下即可回头找回或问出。
学生、研究者、职场人是高频场景，但产品本身不排他；"场景预设"用于自适应不同场景的解析策略，而非圈定人群。

### 1.1 两个版本（Notiee / Notiee+）

同一份源码，通过 **Xcode target + 编译标志隔离**编译出两个独立上架的 App，商业模式与 AI 来源完全不同：

| | **Notiee**（免费内购版） | **Notiee+**（买断 BYOK 版） |
|---|---|---|
| 商业模式 | 免费下载 + 订阅 Pro（¥18/月） | 一次性买断 |
| AI 来源 | 走**自建后端代付**，客户端只送 model ID | 用户自带 endpoint + key，**直连**模型厂商 |
| API Key 位置 | **后端**（客户端永远拿不到） | 用户设备（Keychain 加密） |
| 调用链路 | 客户端 → 后端 → 模型厂商 | 客户端 → 模型厂商 |
| 登录 | **必须 Apple 登录**（鉴权命门） | 可选、轻量本地身份 |
| Scheme / Product | `Notiee` / `Notiee.app` | `Notiee+` / `NotieePlus.app` |
| Bundle ID | `com.idbetterrun.notiee` | `com.idbetterrun.notieeplus` |
| 编译标志 | `#if !NOTIEE_PLUS` | `#if NOTIEE_PLUS` |

**隔离机制**（详见 `AGENTS.md` 与 `docs/Notiee-免费版改造计划.md`）：
- 免费版**独有**的后端相关文件（`AuthService` / `BackendAPIClient` / `EntitlementStore` /
  `BackendAIProcessingService` / `BackendNottiAIService` / `StoreKitService` / `QuotaCard` 等）
  **只勾 `Notiee` target**，Notiee+ 里根本不存在。
- 两版都要编译、只是走不同分支的共享文件 → 统一用 **`#if NOTIEE_PLUS`**，严禁散落 `if 免费版 {}` 运行时判断。
- 中心化 `AppBranding`（`#if NOTIEE_PLUS`）是既定范式，品牌名/图标/文案分叉都收敛于此。

**免费版后端**（`notiee-ping-stream/`，Express + 腾讯云 SCF + MySQL，非流式）承担六件事：
1. **Apple 身份校验**：`identityToken` 验签（含 nonce 防重放）→ 换发自有 30 天 JWT（`/auth/apple`、`/auth/refresh`）。
2. **AI 代付代理**：`/ai/chat`（Notti 文本问答）、`/ai/process`（视觉 + 文本，占 1 篇额度）、`/ai/agent`（工具调用透传）；
   按 provider 适配 OpenAI / Anthropic 两种格式，多厂商路由（DeepSeek / MiniMax / 豆包），key 在服务端。
3. **额度账本**：按「篇」计（一篇拍记扣一篇），月度自然重置，`GET /me/quota` 查询，用尽自动降级本地 OCR 而非硬堵。
4. **订阅校验**：StoreKit 2 凭证上报（`/subscription/verify`）+ App Store 服务端通知（`/apple/notifications`）维护 Pro 档位。
5. **防刷**：Notti 按「模型调用次数」频控（不占篇数），DeviceCheck / App Attest 规划中。
6. **无状态记忆提取**：`POST /ai/memory/extract` 只接收当前消息、成功工具结果和最多 8 条本地候选，校验严格 JSON 后返回 ADD-only proposal；不存储、不记录正文。

**免费档 vs Pro（运行时概念，由后端下发的档位决定，非编译标志）**：额度、可用模型、Notti 能力按档位区分——
免费档锁定便宜模型（如 `deepseek-v4-flash`）、单轮最多召回 5 条本地记忆、单会话 20 轮、无 Agent 模式；
Pro 与 Notiee+ 单轮最多召回 10 条。两档本地记忆存储均不设条数上限。
Pro 全放开。客户端限制仅为 UX，**后端会按档位再校验一遍**，改包无法绕过。收敛到中心化出口
`NottiTierLimits`（`#if NOTIEE_PLUS` 分支恒为"不限"，免费版读 `EntitlementStore`）。

> 现状：两个 App（`com.idbetterrun.notiee` / `com.idbetterrun.notieeplus`）均**尚未上架**，
> 无历史买断用户，因此 EntitlementStore 与后端账户模型不需要老用户 grandfathering 逻辑。

---

## 2. 核心概念

| 概念 | 说明 |
|---|---|---|
| **记录（NoteRecord）** | 核心实体。支持三种来源（`RecordSource`）：拍照 `.photo`、Notti Agent 生成 `.notti`、纯文字 `.text`。`.notti` 仍编码为旧 `"spark"` raw value，以保证旧安装和回滚兼容。 |
| **日程（ScheduledEvent）** | 来自系统日历 / `.ics` 导入 / 手动创建的事件，支持彩色标签分类，用于为记录提供时间上下文。 |
| **特殊日（SpecialDayEvent）** | 节假日、节气、生日等，在 Today 时间轴中标注。 |
| **待办（NoteTodo）** | AI 抽取或手动创建的行动项，可勾选完成、设截止日期与提醒，可独立存在或挂在某条记录下。按截止日分桶管理。 |
| **文件夹 / 标签** | 自建文件夹与彩色标签用于归类记录与事件；另有系统文件夹（收藏 / 未分类 / 今日 / 待处理 / 回收站）；Agent 创建的记录自动归入「Notti 生成」文件夹。 |
| **日程标签（EventTag）** | 为日历事件着色的标签系统，内置 4 个系统标签（个人 / 工作 / 课程 / 临时），支持自定义。 |
| **场景预设（ScenePreset）** | 高效职场人 / 大学生·研究生 / 中学生 / 创作者·研究者，四种预设自动调整 AI 解析策略、课程模式、LaTeX、视觉策略。 |
| **Token 用量** | 每条记录消耗的 token，用于 Review 仪表盘统计与预警。 |
| **深度联想** | 记录详情页底部推荐相关历史笔记（语义向量匹配），同课程相邻时间笔记自动提示续篇关系。 |
| **Notti** | 内置 AI 对话助手，可化身 Agent 调用工具操作笔记、日程、待办与记忆。支持语义检索（向量召回 + 关键词混合排序）、模型选择与思考强度调节。 |
| **本地账户** | 本地身份标识（昵称 + 头像），仅存本机设备，免注册免登录。用于 MeView 个人资料展示与 Notti 个性互动。 |

---

## 3. 应用结构（四大模块）

底栏为四个一级 Tab（定义见 `Models/AppTab.swift`，装配于 `App/RootTabView.swift`）：

| Tab | 图标 | 模块 | 职责 |
|---|---|---|---|
| **Today** | `calendar` | 今日控制中心 | 日程时间轴 + 待办概览 + 今日动态展板 |
| **Snap** | `camera.viewfinder` | 极速相机 | 沉浸式拍照 + 情景感知 |
| **Records** | `book.closed` | 知识库 | 全文检索 + 文件夹层级 + 记录详情 |
| **Notti** | `sparkles` | AI 助手 | 对话 / Agent 工具调用 / 语义检索 |

> 设置与"我"（`MeView` / `SettingsMainView`）不再占用底栏 Tab，从 Today 工具栏进入。
> 系统支持自定义 App 冷启动默认进入的 Tab（`launchCandidates`）。

### 3.1 Today（今日控制中心）

- **时间轴（上半区固定）**：纵向展示今日日程，状态分为已完成 / 进行中（当前命中卡片高亮）/ 即将到来；
  叠加特殊日（节假日、节气、生日）；无日程时显示"无事件"。
- **待办概览**：Today 动态展板顶部展示「当下可执行」的待办（逾期 / 今天截止 / 无截止日期），
  按需分桶展示（`TodoBucketer`：逾期 / 今天 / 明天 / 本周 / 更晚 / 无截止日期）。
  点击可跳转至「所有待办」页面（`AllTodosView`）。
- **今日动态展板（下半区可上滑抽屉）**：今日记录卡片（按时间倒序）。
- 支持彩色标签与自建文件夹快速归类。
- 关键文件：`Features/Today/TodayView.swift`、`TodayViewModel.swift`、`TodoBucketer.swift`、
  `CreateItemSheet.swift`、`TagEditSheet.swift`。

### 3.2 Snap / Capture（极速相机）

- 全屏暗色沉浸式取景框，AVFoundation 自定义快门逻辑。
- 支持缩放预设、闪光灯、连拍（burst），左下角暂存区缩略图、右下角系统相册导入。
- **情景感知叠加层**：取景框顶部半透明显示当前命中的日程，拍照即按日程自动归类（无日程归"未分类"）。
- **无缝连拍**：无阻断式遮罩/弹窗，照片以飞入动画落入暂存区，取景框始终活跃；带圆形进度的加载动画。
- 支持 iOS 18 相机控制（Camera Control）唤起拍照（`CameraControlOverlayView` + `NotieeCameraIntent.swift`）。
- 关键文件：`Features/Capture/CaptureView.swift`、`CaptureViewModel.swift`、`CameraPreviewView.swift`；服务层 `Services/CameraManager.swift`。

### 3.3 Records（知识库管理）

- **全文检索**：跨文件夹名、AI 小标题、AI 摘要、底层 OCR 原始文字。
- **文件夹层级**：系统文件夹 + 暂存区/收件箱 + 多级自建文件夹。
- **课程二级详情页**：左侧纵向时间轴，右侧按"周次 + 日期"倒序排列。
- **记录详情页**：图片查看器、AI 摘要、详细内容（Markdown 渲染）、要点、术语定义、待办、相关笔记推荐；
  各文本区支持长按选择 + 复制/分享。
- 关键文件：`Features/Records/RecordsView.swift`、`RecordDetailView.swift`、`RecordDetailViewModel.swift`、
  `EventDetailView.swift`、`RecordEditSheet.swift`、`HighlightedText.swift`、`SwipeableTodoRow.swift`。

### 3.4 设置与"我"

从 Today 工具栏入口进入 `MeView`（7 个 Section），承载偏好、账户、AI 配置、备份、实验室等：

- **本地账户**：`AccountStore` 管理本地身份标识（昵称 + 头像），仅存本机设备。已登录状态下显示问候语（按时间段自适应：凌晨好/早上好/中午好/下午好/晚上好）与个人头像，点击进入 `ProfileEditView` 编辑资料。未登录状态引导「登录您的 TomaGo 账户」。
- **登录**：`LoginView` 提供 TomaGo 统一登录（含条款勾选 + 协议链接、未勾选时"摇一摇"警示、加载遮罩动画、明暗自适应渐变背景）；`NavigationLink` 跳转 `LocalLoginView` 本地登录（PhotosPicker 选头像 + 文本字段填昵称，一键创建本地身份）。
- **日程管理**：「全部日程」（`AllSchedulesView`）、「所有待办」（`AllTodosView`，按截止日分桶 + 已完成折叠）、「导入日程」（`ImportScheduleView`，含 ICS 解析预览 `EventImportPreviewSheet`，支持内联编辑标题、日期、标签）。
- **回顾**：`ReviewView` — 按事件统计 token 饼图、Top 5 高消耗记录、Notti 累计 token、已删除累计 token、可配置预警阈值。
- **备份与恢复**：`BackupRestoreView` — 一键导出所有记录为 ZIP（含独立 `.tmn` 文件 + 系统分享表单）、从 ZIP 批量导入（解压 → 预览 → 合并到"imported"文件夹）、单文件 .tmn 导入。
- **实验室（Lab）**：`LabFeaturesView` — 低消耗模式（端侧 OCR via ANE）、全功能视觉模式、深度联想模式、高质量云端检索（`notti.semanticSearch.useCloud`）、iCloud 手动同步。部分功能带 `FeatureHintView` 首次访问说明浮层。
- **Notti 设置**：`NottiSettingsView` → 聊天风格（`NottiStyleSettingsView`，6 种预设 + 自定义风格 CRUD）、长期记忆（`NottiMemoryView`，查看/编辑/删除已学记忆条目）、Agent 设置（`AgentSettingsView`，信任等级 + 最大轮数 + 每轮最多工具数）。
- **设置**：`SettingsMainView` — 场景预设、启动页、周数、系统日历选择、课程日历标注、外观（主题/强调色/字体/语言）、AI 自助接入（文本/图像模型 + 自定义模型列表 + 连接测试）、通知、token 阈值、Markdown 渲染。
- **关于 / 法务 / 开源致谢 / 更新日志**：`AboutNotieeView`（含区域感知法务 HTML 路由）、`PrivacyAgreementView`、`OpenSourceAcknowledgmentsView`、`WhatsNewView`。

---

## 4. 记录来源（RecordSource）

Notiee 1.0.4 起引入 `RecordSource` 枚举（`Models/NoteRecord.swift`），拍记（`NoteRecord`）根据创建方式分为三种来源，各有专属视觉标识与详情页行为：

| 来源 | 枚举值 | 创建方式 | 缩略图 | 详情页特征 |
|---|---|---|---|---|
| 拍照记录 | `.photo` | 相机拍摄 / 相册导入 | 照片缩略图 | 显示原图、OCR、AI 摘要（全部区域可见） |
| Notti 生成 | `.notti` | Agent `note_create` 工具 | sparkles 渐变图标 | 无图片预览，仅显示 AI 摘要与内容 |
| 纯文字记录 | `.text` | 手动创建（`NewTextRecordSheet`） | doc.text 图标 | 无图片预览、无 OCR、无 AI 摘要区域 |

- `.notti` 来源的记录自动归入带稳定 `systemRole = nottiGenerated` 的「Notti 生成」系统文件夹（不在自建文件夹列表中显示）。
- `.text` 来源通过 `NewTextRecordSheet` 创建（标题 + 正文文本字段），创建后直接 `processingState = .completed`，不进入 AI 处理管线。
- 详情页 `RecordDetailViewModel` 根据 `source` 控制区域可见性：OCR 仅 `.photo` 显示；摘要区域 `.notti` 仅在摘要 ≠ 内容时显示，`.text` 不显示。
- 旧数据缺少 `source` 字段时默认 `.photo`（向后兼容）。

---

## 5. 本地账户系统

1.0.4 起引入本地身份标识，完全离线，无需注册或联网：

| 组件 | 文件 | 职责 |
|---|---|---|
| `AccountStore` | `Services/AccountStore.swift` (107 行) | `@MainActor` `ObservableObject` 单例，管理本地登录/登出、资料读写、头像加载 |
| `UserProfile` | `Models/UserProfile.swift` | 数据载体：`displayName` / `loginMethod`（`.local` / `.tomago`）/ `avatarRelativePath` |
| `LoginView` | `Features/Settings/LoginView.swift` (310 行) | TomaGo 统一登录页，含 Hero 区域、条款勾选（未勾选时"摇一摇"）、协议链接、加载动画 |
| `LocalLoginView` | `Features/Settings/LocalLoginView.swift` (62 行) | 本地登录表单：`PhotosPicker` 选头像 + `TextField` 填昵称，调用 `AccountStore.localLogin()` |
| `ProfileEditView` | `Features/Settings/ProfileEditView.swift` (89 行) | 编辑页：修改头像/昵称，显示登录方式，提供退出登录按钮 |
| `MeView` | `Features/Settings/MeView.swift` (137 行) | 已登录态显示 `greeting()`（凌晨好/早上好/中午好/下午好/晚上好）+ 头像；未登录引导登录 |

- 头像文件存储于 `~/Library/Application Support/Notiee/avatar/`。
- `greeting(at:)` 根据当前时间返回本地化问候语（zh-Hans/zh-Hant/en 三语）。
- 后续可扩展 TomaGo 统一账户实现多端同步（当前仅本地）。

---

## 6. Notti AI 助手与 Agent

**Notti** 是 Notiee 内置的 AI 对话助手（底栏第四 Tab），既能普通问答，也能切换为 **Agent** 直接操作 App 数据。

### 6.1 对话层（非 Agent 模式）

- `NottiView` / `NottiViewModel`：聊天界面、消息流、动态背景（`NottiBackgroundView`）、输入栏（`NottiInputBar`）、气泡（`NottiChatBubble`）。
- **会话与历史**：`NottiConversationStore`、`NottiConversationRepository`、`NottiHistoryStore` / `NottiHistoryView` 管理多会话与历史记录。
- **长期记忆**：`NottiMemoryRepository` / `NottiMemoryCoordinator` / `NottiMemoryView` 管理加密快照、证据、待确认项、提取队列、混合召回与生命周期；回答模型没有直接写权限。
- **引用**：接地于拍记的回答以行内 `[来源N]` 标记，自动解析为 `Citation` 引用卡片（`NottiCitationRow`）。非 Agent 问答使用近期锚点与语义命中的有界拍记集合，不全量注入记录库。
- **模型与思考强度**：`NottiModelPreferences` / `NottiModelChip` 支持 Notti 局部覆盖模型；思考强度由 `ModelThinkingPolicy` / `ThinkingCapability` 按 Provider 注入 payload。
- **意图识别**：`NottiIntentDetector` 判断用户消息意图；如果非 Agent 模式下用户发出类似操作请求的消息，会主动提示切换 Agent。
- 非 Agent 模式下，Notti 也能看到只读的"即将到来的日程"作为上下文。

### 6.2 Agent 层（工具调用）

位于 `Features/Notti/Agent/`，采用经典的"工具调用循环"：

- **`AgentExecutor`**：最多 **5 轮**迭代的 Reason-Act 循环；把工具以 OpenAI / Anthropic 两种 schema 暴露给模型，
  解析模型返回的 `toolCalls`，逐个执行并把结果回填进对话，直至模型给出最终回答或某工具要求终止。
- **`AgentToolRegistry`**：工具注册表，按信任等级过滤可用工具，并生成 OpenAI/Anthropic 的函数/工具 JSON Schema。
- **`AgentTrustManager`**：信任等级（`AgentTrustLevel`）决定 Agent 能调用哪些工具（读 vs 写权限分级）。
- **`AgentActionStore`**：持久化 Agent 执行过的动作记录。
- **`AgentToolPresentation`**：把工具调用过程友好地呈现到聊天时间线（`NottiAgentTimelineView`）。

**内置工具（`Features/Notti/Agent/Tools/`） 共 18 个**：

| 工具 | 能力 | 权限 |
|---|---|---|
| `DateInfoTool` | 查询日期/星期/节气等信息 | read |
| `CalendarQueryTool` | 查询日程 | read |
| `ScheduleCreateTool` | 创建日程 | write |
| `ScheduleUpdateTool` | 更新日程 | write |
| `ScheduleDeleteTool` | 删除日程 | write |
| `NoteSearchTool` | **语义 + 关键词混合检索**拍记（`SemanticSearchEngine`） | read |
| `NoteGetDetailTool` | 获取笔记详情 | read |
| `NoteCreateTool` | 创建笔记 | write |
| `NoteUpdateTool` | 更新笔记 | write |
| `NoteDeleteTool` | 删除笔记 | write |
| `TodoListTool` | 列出待办 | read |
| `TodoCreateTool` | 创建待办 | write |
| `TodoCompleteTool` | 完成待办 | write |
| `TodoDeleteTool` | 删除待办 | write |
| `MemorySearchTool` | 有界检索 Notti 相关记忆；仅在成功 Agent 回合后记录实际使用 | read |
| `MemoryForgetTool` | 永久删除用户明确指定的记忆 | destructive |
| `WebSearchTool` | 联网搜索（`WebSearchTool`，需在设置中配置搜索能力） | read |
| `WebFetchTool` | 抓取指定 URL 网页正文（SSRF 防护，仅 http/https 公网，2MB 上限，10s 超时） | read |

> 工具协议见 `AgentToolProtocol.swift`，每个工具声明 `name` / `description` / `parametersSchema` / `permission`。

### 6.3 模型与思考强度选择器

Notti 对话界面顶部设有独立于全局配置的模型与思考选择器：

- **`NottiModelChip`**：胶囊形菜单，下拉列出可用模型，选中项显示 checkmark，模型切换仅影响当前 Notti 会话。
- **`NottiAgentChip`**：Agent 模式切换按钮（bolt 图标），开启后玻璃化高亮，模型可调用工具。
- **`ThinkingCapability`**：按 AI 服务商注入思考强度 payload：
  - 分级制（豆包/自定义/MiniMax）：`极简/minimal`、`低/low`、`中/medium`、`高/high`，注入 `reasoning_effort` 参数。
  - 开关制（通义千问/DeepSeek）：`off/on`，注入 `enable_thinking` 或 `reasoning_effort` minimal/high。
  - Vision 模型无思考支持。
- **`NottiModelPreferences`**：Notti 专属模型覆盖（`modelOverride`）与思考等级（`thinkingLevelID`），持久化于 UserDefaults，不干扰全局 AI 配置。

### 6.4 聊天风格与个性化

- **`NottiStyleSettingsView`**：6 种预设聊天风格（默认 / 温柔知心 / 犀利毒舌 / 简洁高效 / 幽默风趣 / 学究严谨）+ 自定义风格 CRUD（添加/编辑/删除任意风格指令）。风格以 system prompt 注入当前对话。
- **`NottiMemoryView`**：搜索并按分类查看使用中、待确认与已归档记忆；支持敏感项确认、编辑、恢复、导出、永久删除和清空全部。
- **`AgentSettingsView`**：Agent 信任等级选择（谨慎 / 标准 / 完全信任）、最大迭代轮数、每轮最多工具数。
- **`NottiPrivacySheet`**：独立版本化的记忆隐私同意书；说明记忆/向量本地加密且不进 iCloud，只临时发送当前消息、已确认工具结果和有界命中记忆，并明确敏感记忆确认及联网读取边界。
- **`NottiIntentDetector`**：本地启发式意图检测，非 Agent 模式下若用户发出操作指令，主动提示切换到 Agent。

---

## 7. 语义检索引擎 / RAG

Notiee 实现了一套**混合语义检索**系统，用于 Agent 的 `NoteSearchTool`。不同于最初的全量上下文注入或纯关键词搜索，
新架构将每条拍记计算为高维语义向量（embedding），通过**关键词保底 + 余弦相似度阈值**的组合策略进行混合排序。

### 7.1 服务架构

```
NottiViewModel.makeAgentExecutor()
  └── SemanticSearchEngine  ←  HybridEmbeddingService  ←  LocalEmbeddingService  (Apple NLEmbedding, 端侧)
      搜索协调 / 懒补算                                       CloudEmbeddingService  (云端 embeddings API, 可选)
                                    │
                              EmbeddingIndex  (侧车持久化 JSON, 与 NoteRecord 解耦)
                                    │
                              SemanticRanker  (关键词 floor + cosine 阈值 = 0.45)
```

### 7.2 核心组件

| 组件 | 文件 | 职责 |
|---|---|---|
| `EmbeddingService` 协议 | `Services/Semantic/EmbeddingService.swift` | 向量服务抽象，声明 `modelIdentifier` + `embed(_:)` |
| `LocalEmbeddingService` | `Services/Semantic/LocalEmbeddingService.swift` | Apple `NLEmbedding` 端侧句向量，优先简体中文回退英文 |
| `CloudEmbeddingService` | `Services/Semantic/CloudEmbeddingService.swift` | 云端 OpenAI 兼容 embeddings API，复用 Notti 文本模型 endpoint/key，智能改写 `/chat/completions` → `/embeddings` |
| `HybridEmbeddingService` | `Services/Semantic/HybridEmbeddingService.swift` | 选择策略 + 降级链：云端开关开 → 云端；失败/关闭 → 本地 |
| `EmbeddingIndex` | `Services/Semantic/EmbeddingIndex.swift` | 旁路向量持久化（`embedding-index.json`），存 `[UUID: EmbeddingEntry]`（vector + model + contentHash），与 NoteRecord JSON 解耦，内容变更后自动重算 |
| `SemanticSearchEngine` | `Services/Semantic/SemanticSearchEngine.swift` | 懒计算 + 缓存复用：为每条候选拍记 `ensureVector`（已有 + hash 匹配则复用，否则调用 embedding 重算），结果传给 ranker |
| `SemanticRanker` | `Services/Semantic/SemanticRanker.swift` | 混合排序：关键词命中 → 基础分 +1.0 + cosine；关键词未命中但 cosine ≥ 0.45 → 仅 cosine；否则不返回 |
| `VectorMath` | `Services/Semantic/VectorMath.swift` | 余弦相似度纯函数实现 |
| `RecordEmbeddingText` | `Services/Semantic/EmbeddingService.swift` | 拍记拼接（title+summary+ocrText 截断 2000 字）+ SHA256 内容哈希（跨进程稳定） |

### 7.3 工作流

1. **Agent 调用 `note_search`**：`NoteSearchTool.execute` 将 query 传给 `SemanticSearchEngine.search`。
2. **懒补算**：对候选拍记，`ensureVector` 检查 `EmbeddingIndex`——若存在且 contentHash + model 匹配则复用；否则调用 `HybridEmbeddingService.embed` 重新计算并写入索引。
3. **混合打分**：`SemanticRanker.rank`：
   - 关键词命中（title/summary/ocrText 不区分大小写子串）→ `cosine + 1.0`
   - 关键词未命中但 cosine ≥ **0.45** → `cosine`
   - 否则丢弃
4. **Top-K 返回**：按分数降序取前 `limit` 条。

### 7.4 后台回填

`SemanticSearchEngine.backfill(records:)` 可在启动时批量预计算拍记向量，避免首次搜索时全部懒载。

### 7.5 降级路径

- `HybridEmbeddingService` 云端不可用时自动降级到本地 `NLEmbedding`。
- `NoteSearchTool` 如果未注入 `searchEngine`（如测试环境），自动回退到纯关键词搜索。
- `LocalEmbeddingService` 不可用时抛 `EmbeddingError.unavailable`，语义失效但关键词仍正常工作。

---

## 8. 深度联想 / 相关笔记推荐

记录详情页底部提供两项关联发现能力，帮助用户串联碎片化笔记：

### 8.1 相关内容推荐

- 详情页加载时，为当前拍记计算语义向量，与历史拍记的向量做余弦相似度匹配。
- 使用独立的 `EmbeddingIndex.related`（`related-notes-index.json`），与搜索索引完全隔离，浏览时**不触发云端请求**。
- 匹配阈值设为 **0.6**（高于搜索的 0.45），保底返回 top **3** 条相关记录。
- 结果在详情页底部以「相关内容」Section 展示，每条为 `NavigationLink` 可跳转。

### 8.2 续篇笔记检测

- 同一日程事件下，时间相邻（48 小时内）的拍记自动判定为续篇关系。
- 当前记录的"上一篇"在详情页顶部以「续篇笔记」链接显示。
- 实现位于 `RecordDetailViewModel` 的 `continuationRecord` 计算属性。

### 8.3 开关控制

- 深度联想模式在实验室中通过「深度联想模式」开关控制（`labDeepAssociationModeEnabled`）。
- 关闭后详情页不再计算向量或展示相关内容。

---

## 9. AI 处理流水线

拍照后，记录进入异步处理队列（`AIPipelineManager` + `Services/AIProcessingService.swift`）：

```
Capture → NoteRecord(.pending) → 入队
        → 阶段一：Vision LLM   OCR(含 LaTeX) + 100 字内核心摘要
        → 阶段二：Text  LLM    12 字小标题 + 要点/术语 + 待办抽取
        → applyAIResult → NoteRecord(.completed) + tokenUsage
```

- **服务实现**：`RealAIProcessingService`（真实 API）+ `MockAIProcessingService`（无 Key / 测试回退）。
  API 客户端 `AIAPIClient.swift`（含 cloud embedding 调用的 `OpenAICaller.callEmbedding`），
  Prompt 由 `AIPromptProvider.swift` 提供，兼容 OpenAI / Anthropic 协议。
- **处理状态**（`AIProcessingState`）：`pending` → `processing` → `completed` / `failed` / `deadLetter`。
- **异常与重试**：API 限频时指数退避；连续失败移入死信队列（dead letter），前端支持手动重试（`retryAIProcessing`）。
- **完全离线**：本地缓存，网络恢复后自动续传。
- **低消耗模式**：可走端侧 OCR（`LocalOCRService.swift`，Apple Neural Engine）减少云端 token 消耗。
- **触发时机**：受 `aiEnabled` 与 `autoProcessAfterCapture` 控制，`live()` 默认 `autoProcess = true`。

---

## 10. 数据模型

核心模型位于 `Notiee/Models/`：

| 模型 | 说明 |
|---|---|
| **`NoteRecord`** | 笔记记录主体：`eventID` / `folderID` / `capturedAt` / `localImagePaths` / `title` / `ocrText` / `summary` / `detailedContent` / `source` (`RecordSource`) / `processingState` / `keyPoints` / `definitions` / `isFavorite` / `isDeleted` / `tokenUsage` / `aiRetryCount` / `deviceName` 等。 |
| **`RecordSource`** | 记录来源枚举：`.photo`（拍照/相册）、`.notti`（Agent 创建）、`.text`（手动文字记录）；`.notti` 的稳定持久化值仍为旧 `"spark"`。 |
| **`KeyDefinition`** | 术语定义（`term` + `explanation`）。 |
| **`NoteTodo`** | 待办项（内容、完成态、截止日期 `dueDate`、提醒、可关联记录）。 |
| **`ScheduledEvent`** | 日程/课程/会议事件，支持 `tagID` 关联彩色标签。 |
| **`SpecialDayEvent`** | 节假日 / 节气 / 生日等特殊日。 |
| **`CustomFolder`** / **`EventTag`** | 自建文件夹 / 日程彩色标签。 |
| **`ScenePreset`** | 四种使用场景预设。 |
| **`AIModelConfiguration`** / **`AIProvider`** | AI 模型配置与服务商。 |
| **`ModelThinkingPolicy`** / **`ThinkingCapability`** | 模型"思考强度"策略与能力（按 Provider 注入 payload）。 |
| **`AIProcessingState`** (+`+UI`) | AI 处理状态机及其 UI 映射。 |
| **`UserProfile`** | 用户资料（`displayName` / `loginMethod` / `avatarRelativePath`）。 |
| **`LoginMethod`** | 登录方式枚举：`.local`（本地免注册）/ `.tomago`（TomaGo 统一账户）。 |
| **`NottiModelPreferences`** | Notti 会话级模型覆盖（`modelOverride` + `thinkingLevelID`）。 |
| **`NottiMemory`** | 带稳定 UUID、分类、持久度、状态、主题、实体、关键词、时间、证据计数、最近使用、敏感级别、关联和修订历史的本地记忆。 |
| **`AppTab`** | 一级 Tab 枚举。 |
| **`ScheduleActivityAttributes`** | Live Activity（灵动岛/锁屏）属性。 |
| **`TMNModels`** | `.tmn` 备份归档的数据结构。 |
| **`UIDevice+ModelName`** | 设备型号名工具扩展。 |

---

## 11. 状态管理与架构

整体为 **SwiftUI + MVVM**，状态中心化在 **`NotieeStore`**（`@MainActor` `ObservableObject`）。

`NotieeStore` 本身不直接持有全部逻辑，而是**组合四个 Manager**，并通过 **Combine** 把它们的 `@Published` 状态镜像到自身，供视图订阅：

```
                ┌─────────────────────────────┐
   Views ──────▶│        NotieeStore          │  @MainActor / @Published
                │  (门面 + Combine 聚合 + 委派) │
                └───┬───────┬───────┬───────┬──┘
                    │       │       │       │
            RecordManager  CalendarManager  FolderTagManager  AIPipelineManager
            (记录/待办)     (日程/特殊日/匹配)  (文件夹/标签)      (AI 异步队列)
                    │
            ScheduleMatcher（拍照→日程匹配）

独立服务（不挂载 Store）：
  AccountStore（本地账户身份）  EventTagStore（标签持久化）
  EmbeddingIndex（拍记向量侧车） NottiModelPreferences（Notti 模型偏好）
  NottiMemoryRepository（加密记忆快照 + 加密记忆向量侧车）
```

- **Manager 职责**
  - `RecordManager`：记录与待办的 CRUD、查询（收藏/已删/今日/待处理/所有待办）、token 统计、Top N、搜索。
  - `CalendarManager`：系统日历同步、当前事件命中、特殊日检测、周次格式化、忽略/恢复日历事件、Live Activity 开关。
  - `FolderTagManager`：自建文件夹与标签、事件↔标签映射。
  - `AIPipelineManager`：入队、重试、应用 AI 结果（通过 `AIPipelineRecordAccess` 反向访问 Store）。
- **独立服务**
  - `AccountStore`：`@MainActor` `ObservableObject` 单例，本地身份登录/登出/资料管理，通过 `MeView` 直接绑定。
  - `EventTagStore`：日程标签的 JSON 持久化与 CRUD，在 `FolderTagManager` 中聚合。
  - `NottiModelPreferences`：Notti 会话级模型覆盖与思考强度偏好，独立于全局 AI 配置。
  - `NottiMemoryRepository`：actor 单写入口；本地 AES-GCM 快照、待确认项、提取队列、修订和可重建向量侧车。
- **持久化**：`JSONNoteRecordStore` / `JSONCustomFolderStore` / `JSONEventTagStore` / `JSONScheduledEventStore`（本地 JSON）；
  向量单独存储在 `EmbeddingIndex`（`embedding-index.json` 与 `related-notes-index.json`，与记录数据解耦）；
  Notti 记忆快照写入 `notti_memory_v1.enc`，记忆向量写入独立加密侧车；偏好走 `UserDefaultsAppSettingsStore`（键集中在 `Utils/UserDefaultsKeys.swift`）；API Key 与记忆 DEK 存于 **Keychain**。
- **拍照匹配**：`ScheduleMatcher` 处理课表冲突/重叠（关联最近创建/更新的日程，可手动切换）。
- **两套初始化**：`NotieeStore.live(...)` 从磁盘加载真实数据；`NotieeStore.sample(...)` 提供预览/测试样例数据。

---

## 12. 技术栈与依赖

| 层 | 技术 |
|---|---|
| UI | 100% SwiftUI，系统毛玻璃材质，弹簧动画，SF Symbols |
| 状态 | `NotieeStore` + 四 Manager + Combine |
| 持久化 | 本地 JSON、UserDefaults、Keychain |
| 语义检索 | Apple `NLEmbedding` 端侧句向量 + 云端 OpenAI 兼容 embeddings API + 余弦相似度 + 关键词底 |
| 相机 | AVFoundation（缩放预设、闪光、连拍） |
| 日历 | EventKit（节假日/生日/节气检测、课程日历标注） |
| AI | 异步 `Task` 队列，OpenAI/Anthropic 兼容 API |
| Live Activity | ActivityKit + Widget Extension |
| 通知 | `UNUserNotificationCenter` |
| 权限 | 中心化 `SystemPermissionManager` |
| 端侧 OCR | Vision / ANE（`LocalOCRService`） |

**Swift Package Manager 依赖**：

| 包 | 用途 |
|---|---|
| [lottie-ios](https://github.com/airbnb/lottie-ios) | Lottie 动画渲染 |
| [NetworkImage](https://github.com/gonzalezreal/NetworkImage) | 异步图片加载 + 磁盘缓存 |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown 渲染 |
| [swift-cmark](https://github.com/swiftlang/swift-cmark) | CommonMark 解析 |
| [OnboardingKit](https://github.com/danielsaidi/OnboardingKit) | 新手引导 |
| [PageView](https://github.com/danielsaidi/PageView) | 分页滚动视图 |
| [WhatsNewKit](https://github.com/SvenTiigi/WhatsNewKit) | 版本更新日志 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | `.tmn` 归档压缩 |

> **AI 来源按版本分叉**（见 §1.1）：**Notiee+（BYOK）** 通过用户自带的大模型 API **直连**完成；
> **Notiee（免费版）** 走自建后端 `notiee-ping-stream/`（Express + 腾讯云 SCF + MySQL，非流式）**代付代理**，
> key 在服务端。无论哪版，笔记数据均**本地离线优先**存储于设备。
> （PRD 早期设想的 FastAPI + Redis + PostgreSQL 技术栈未采用，以 `notiee-ping-stream/` 的实际实现为准。）

---

## 13. iOS 26 Liquid Glass 适配

Notiee 全面适配 iOS 26 全新的 Liquid Glass 设计语言，同时保持 iOS 18–25 兼容回退。

**核心适配层**（`Utils/GlassStyle.swift`，64 行）：

| 适配方法 | iOS 26 效果 | 低版本回退 |
|---|---|---|
| `glassIconButton(prominent:)` | `.glass` / `.glassProminent` 按钮样式 | 普通 button style |
| `glassSurface(in:prominent:)` | `.glassEffect` 玻璃材质 | `.ultraThinMaterial` |
| `AdaptiveGlassContainer` | `GlassEffectContainer` 包裹 | 直接透传内容 |

**应用范围**：

| 区域 | 玻璃化组件 |
|---|---|
| **Today** | 头像按钮、加号按钮（加号为 prominent accent 玻璃） |
| **Notti** | 新建/历史按钮、输入栏背景、发送按钮、Agent chip、重试 chip、模型选择胶囊 |
| **相机** | 闪光灯、变焦预设、文件夹按钮、单拍/连拍切换胶囊 |
| **Tab Bar** | 系统自动玻璃化，无需额外处理 |

---

## 14. 日历日程标签系统

为日程事件提供可定制的彩色标签，在 Today 时间轴和拍照时提供视觉区分。

| 组件 | 文件 | 职责 |
|---|---|---|
| `EventTag` 模型 | `Models/EventTag.swift` | 标签实体：`id` / `name` / `colorHex` / `isSystem`，内置 4 个系统标签（个人 #007AFF / 工作 #FF9500 / 课程 #34C759 / 临时 #AF52DE），系统标签使用固定 UUID 保证稳定性 |
| `EventTagStore` | `Services/EventTagStore.swift` | JSON 持久化（`Notiee/tags.json`），提供 CRUD 操作 |
| `TagEditSheet` | `Features/Today/TagEditSheet.swift` | 新建标签表单：名称文本字段 + `ColorPicker` |
| `EventCardView` | `Components/EventCardView.swift` | 日程卡片左侧显示标签色条 + 标签名 |
| `FolderTagManager` | `Services/Managers/FolderTagManager.swift` | 在 Store 中暴露 `customTags`，供视图绑定 |
| `EventImportPreviewSheet` | `Features/Settings/EventImportPreviewSheet.swift` | ICS 导入预览中支持行内 `Picker` 选择标签 |

- 系统标签不可删除，自定义标签可自由增删。
- 标签绑定到 `ScheduledEvent.tagID`，一个日程一个标签。
- 颜色通过 `Color(hex:)` 扩展解析，支持 iOS 26 Liquid Glass 环境。

---

## 15. 目录结构

```text
Notiee/
├── App/
│   ├── NotieeApp.swift            # @main 入口
│   └── RootTabView.swift          # 四 Tab 布局 + Camera Control + .tmn 打开
├── Features/
│   ├── Today/                     # 今日控制中心 + 待办分桶 (TodoBucketer)
│   ├── Capture/                   # 极速相机
│   ├── Records/                   # 知识库 + 记录详情
│   ├── Settings/                  # 我、设置、登录、备份、Review、Lab、Notti 设置、所有待办 (AllTodosView)
│   └── Notti/                     # AI 助手
│       └── Agent/                 # Agent 执行器、注册表、信任、工具
│           └── Tools/             # 18 个 Agent 工具
├── Models/                        # 领域模型
├── Services/                      # 基础设施
│   ├── NotieeStore.swift          # 中心状态门面
│   ├── Managers/                  # RecordManager / CalendarManager / FolderTagManager / AIPipelineManager
│   ├── Semantic/                  # 语义检索引擎 (8 文件)
│   │   ├── EmbeddingService.swift # 向量协议 + RecordEmbeddingText + SHA256 哈希
│   │   ├── LocalEmbeddingService.swift  # Apple NLEmbedding 端侧句向量
│   │   ├── CloudEmbeddingService.swift  # 云端 embeddings API
│   │   ├── HybridEmbeddingService.swift # 本地/云端选择 + 降级链
│   │   ├── EmbeddingIndex.swift         # 侧车向量持久化 (embedding-index + related-notes-index)
│   │   ├── SemanticRanker.swift         # 关键词底 + cosine 阈值混合排序
│   │   ├── SemanticSearchEngine.swift   # 懒补算 + 缓存 + 协调器（含 related() 深度联想）
│   │   └── VectorMath.swift             # 余弦相似度
│   ├── CameraManager.swift        # AVFoundation 会话
│   ├── CalendarService.swift      # EventKit + 特殊日检测
│   ├── ScheduleMatcher.swift      # 拍照→日程匹配
│   ├── RealAIProcessingService.swift / MockAIProcessingService.swift
│   ├── AIAPIClient.swift / AIPromptProvider.swift
│   ├── LocalOCRService.swift      # 端侧 OCR (ANE)
│   ├── LiveActivityManager.swift / NotificationManager.swift
│   ├── ICloudSyncService.swift / SyncQueue.swift / NetworkMonitor.swift
│   ├── TMNExportService.swift / TMNImportService.swift / RecordMigrator.swift
│   ├── AccountStore.swift         # 本地账户身份管理
│   ├── EventTagStore.swift        # 日程标签持久化 (tags.json)
│   ├── ImageSaver.swift           # 保存图片到系统相册
│   ├── LocalImageStore.swift      # 本地拍摄图片文件管理
│   ├── JSONNoteRecordStore / JSONCustomFolderStore / JSONEventTagStore / JSONScheduledEventStore
│   └── SystemPermissionManager
├── Components/                    # 可复用视图（EventCard / RecordCard / TodoRow / FeatureHintView ...）
├── Utils/                         # NotieeColors / LottieView / Logger / GlassStyle / UserDefaultsKeys
├── Legal/                         # 法务 HTML（UserAgreement + PrivacyPolicy × 4 语言 = 8 文件）
├── en.lproj / zh-Hans.lproj / zh-Hant.lproj   # 本地化 (560+ strings)
NotieeWidget/                      # Widget + Live Activity（灵动岛/锁屏）
NotieeTests/                       # 38 个单元测试
docs/                              # 文档（含本 Wiki、PRD、技术文档、官网规划等）
```

---

## 16. 备份与同步

- **TMN 归档**：`.tmn` 是基于 ZIP 的备份归档（`ZIPFoundation`），全保真导出/导入记录（含图片、摘要、要点、待办）。
  - 导出：`TMNExportService`；导入：`TMNImportService`。
  - 通过 `onOpenURL` 直接打开 `.tmn` 文件，弹出 `TMNImportPreviewSheet` 预览后导入。
- **BackupRestoreView**（`Features/Settings/BackupRestoreView.swift`，338 行）：完整的备份管理界面，三种工作流：
  1. **一键导出所有记录** → 所有记录打包为独立 `.tmn` → 合并 ZIP → 系统 `UIActivityViewController` 分享。
  2. **从 ZIP 压缩包恢复** → 解压 → 枚举 `.tmn` → `BackupImportPreviewSheet` 预览 → 批量导入到「imported」文件夹。
  3. **导入单个 .tmn 文件** → `TMNImportService.importTMN()` → `TMNImportPreviewSheet` 预览确认。
- **iCloud 同步**：`ICloudSyncService` + `SyncQueue` 提供手动 iCloud Drive 同步（实验室功能）；支持上传/下载 `.tmn` 文件与合并逻辑。CloudKit 自动同步在规划中。
- **网络监测**：`NetworkMonitor` 驱动离线缓存与恢复后重传。
- **迁移**：`RecordMigrator` 处理历史数据结构迁移。`ImageSaver` 提供保存图片到系统相册的能力。

---

## 17. 权限与隐私

| 权限 | 用途 |
|---|---|
| 相机 | 拍摄白板/笔记照片 |
| 麦克风 | 语音录制 |
| 相册 | 导入已有图片 |
| 日历 | 读取系统日历进行日程匹配 |
| 语音识别 | 语音转文字 |
| 通知 | 事件开始/结束提醒 |

- 权限统一由 `Services/SystemPermissionManager.swift` 管理。
- API Key 加密存储于 **iOS Keychain**，不上传服务器。
- 法务文件随包内置（隐私政策 / 用户协议，含简繁英 HTML：zh-Hans / zh-Hant-HK / zh-Hant-TW / en，按 App 语言与设备地区自动路由）

---

## 18. 本地化

UI 文案覆盖三种语言（三套 `Localizable.strings`）：

- **English**（`en.lproj`）
- **简体中文**（`zh-Hans.lproj`）
- **繁體中文**（`zh-Hant.lproj`）

语言切换由 `UserDefaults` 中的 `notiee.language` 控制（`system` / `zh-Hans` / `zh-Hant` / `en`），
通过覆写 `AppleLanguages` 实现即时切换（需重启 App）。

**法务文件本地化策略**：隐私政策与用户协议以 HTML 内嵌于 `Notiee/Legal/`，
按 App 语言与设备地区自动路由四个变体：

| App 语言 | 设备地区 | 加载文件 |
|---|---|---|
| 简体中文（zh-Hans） | — | `*_zh-Hans.html` |
| 繁體中文（zh-Hant） | 非 TW | `*_zh-Hant-HK.html`（港澳繁體） |
| 繁體中文（zh-Hant） | TW | `*_zh-Hant-TW.html`（台灣繁體） |
| English（en） | — | `*_en.html` |
| 系统默认 | 按 `Locale.current` 推断 | 同上规则，无法匹配时回退 `zh-Hans` |

路由逻辑位于 `AboutNotieeView.swift` 的 `legalLocaleSuffix` 计算属性。

---

## 19. 构建与测试

环境要求：**iOS 18.0+ · Xcode 16.0+ · Swift 6.0+**

```bash
open Notiee.xcodeproj
# Cmd+R 运行，Cmd+U 运行测试
```

**测试**：`NotieeTests/` 含 **38 个**单元测试，覆盖 Store、各 Manager、ViewModel、
日程匹配（`ScheduleMatcherTests`）、AI Mock（`MockAIProcessingServiceTests`）、
Notti 记忆/迁移/召回与 Agent 工具（`Notti*Tests`、`*ToolTests`）、思考策略（`ModelThinkingPolicyTests`/`ThinkingCapabilityTests`）、
语义检索（`SemanticSearchEngineTests` / `SemanticRankerTests` / `EmbeddingIndexTests` /
`LocalEmbeddingServiceTests` / `HybridEmbeddingServiceTests` / `RecordEmbeddingTextTests`）、
待办分桶（`TodoBucketerTests`）等。

---

<sub>本 Wiki 基于当前 main 源码整理：双版本架构（Notiee 免费后端订阅版 / Notiee+ 买断 BYOK 版，同源码 `#if NOTIEE_PLUS` 隔离）+ Notti 本地加密记忆与有界混合召回 + 免费版无状态提取后端 + Agent 18 工具 + 拍记混合语义检索 + 深度联想 + 本地账户系统 + 三种记录来源（照片/Notti/文字）+ 日程彩色标签 + iOS 26 Liquid Glass 适配 + 四语种法务本地化。如与早期 README/PRD 表述不一致，以源码为准。</sub>
