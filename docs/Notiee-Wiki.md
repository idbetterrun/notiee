# Notiee Wiki

> **Notiee** — Schedule-Aware AI Rapid Note Capture / 日程感知 AI 极速拍记
> 一款 iOS 原生 SwiftUI 应用：举起相机拍下白板、课件或会议笔记，自动关联当前日程，
> 经 AI 流水线完成 OCR、摘要、要点提炼与待办抽取，把碎片化的"拍照"沉淀为结构化的"知识流"。

| 项目 | 信息 |
|---|---|
| 平台 | iOS 18.0+ |
| 语言 | Swift 6.0+ |
| 构建 | Xcode 16.0+ |
| 架构 | SwiftUI + MVVM + 中心化 Store/Manager 组合 |
| 数据 | 离线优先（本地 JSON / UserDefaults / Keychain） |
| 版本 | v1.0.3+（含 Spark AI 助手） |
| 许可 | Proprietary |

---

## 目录

1. [产品定位](#1-产品定位)
2. [核心概念](#2-核心概念)
3. [应用结构（四大模块）](#3-应用结构四大模块)
4. [Spark AI 助手与 Agent](#4-spark-ai-助手与-agent)
5. [AI 处理流水线](#5-ai-处理流水线)
6. [数据模型](#6-数据模型)
7. [状态管理与架构](#7-状态管理与架构)
8. [技术栈与依赖](#8-技术栈与依赖)
9. [目录结构](#9-目录结构)
10. [备份与同步](#10-备份与同步)
11. [权限与隐私](#11-权限与隐私)
12. [本地化](#12-本地化)
13. [构建与测试](#13-构建与测试)

---

## 1. 产品定位

**核心痛点**：学生与职场人在课堂、会议中频繁拍摄 PPT、黑板、白板，课后照片散落在系统相册里，
难以检索、懒得整理，知识点无法沉淀。

**解决方案**：
- **日程对应**：导入系统日历或 `.ics` 课表，在按下快门的瞬间自动把照片关联到当前时间段的课程/会议，赋予照片上下文。
- **AI 结构化**：后台异步队列调用用户自带的大模型 API，对图片做 OCR（含 LaTeX）、生成摘要、提炼小标题、抽取待办。
- **离线优先**：无网时本地缓存秒开，网络恢复后自动续跑 AI 处理。

**目标人群**：学生、研究者、需要高频记录的职场人。通过"场景预设"自适应不同人群的解析策略。

---

## 2. 核心概念

| 概念 | 说明 |
|---|---|
| **记录（NoteRecord）** | 一次拍摄产生的核心实体，包含原图、OCR 文本、AI 摘要、详细内容、要点、术语定义、待办与 token 用量。 |
| **日程（ScheduledEvent）** | 来自系统日历 / `.ics` 导入 / 手动创建的事件，用于为记录提供时间上下文。 |
| **特殊日（SpecialDayEvent）** | 节假日、节气、生日等，在 Today 时间轴中标注。 |
| **待办（NoteTodo）** | AI 抽取或手动创建的行动项，可勾选完成、设提醒，可独立存在或挂在某条记录下。 |
| **文件夹 / 标签** | 自建文件夹与彩色标签用于归类记录与事件；另有系统文件夹（收藏 / 未分类 / 今日 / 待处理 / 回收站）。 |
| **场景预设（ScenePreset）** | 高效职场人 / 大学生·研究生 / 中学生 / 创作者·研究者，四种预设自动调整 AI 解析策略、课程模式、LaTeX、视觉策略。 |
| **Token 用量** | 每条记录记录消耗的 token，用于 Review 仪表盘统计与预警。 |
| **Spark** | 内置 AI 对话助手，可化身 Agent 直接调用工具操作笔记、日程、待办与记忆。 |

---

## 3. 应用结构（四大模块）

底栏为四个一级 Tab（定义见 `Models/AppTab.swift`，装配于 `App/RootTabView.swift`）：

| Tab | 图标 | 模块 | 职责 |
|---|---|---|---|
| **Today** | `calendar` | 今日控制中心 | 日程时间轴 + 今日动态展板 |
| **Snap** | `camera.viewfinder` | 极速相机 | 沉浸式拍照 + 情景感知 |
| **Records** | `book.closed` | 知识库 | 全文检索 + 文件夹层级 + 记录详情 |
| **Spark** | `sparkles` | AI 助手 | 对话 / Agent 工具调用 |

> 设置与"我"（`MeView` / `SettingsMainView`）不再占用底栏 Tab，从模块内入口进入。
> 系统支持自定义 App 冷启动默认进入的 Tab（`launchCandidates`）。

### 3.1 Today（今日控制中心）

- **时间轴（上半区固定）**：纵向展示今日日程，状态分为已完成 / 进行中（当前命中卡片高亮）/ 即将到来；
  叠加特殊日（节假日、节气、生日）；无日程时显示"无事件"。
- **今日动态展板（下半区可上滑抽屉）**：AI 提取的待办列表（可勾选）、今日记录卡片（按时间倒序）。
- 支持彩色标签与自建文件夹快速归类。
- 关键文件：`Features/Today/TodayView.swift`、`TodayViewModel.swift`、`CreateItemSheet.swift`、`TagEditSheet.swift`。

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

从模块入口进入，承载偏好、登录、AI 配置、备份、实验室等：

- **登录**：TomaGo 统一登录 + 本地登录（`LoginView` / `LocalLoginView`），含加载遮罩与未勾选条款时的"摇一摇"警示，明暗自适应。
- **AI 自助接入**：文本大模型、图像大模型、自定义模型列表、连接测试（`AIConfigurationView`、`CustomModelsListView`、`AIFeatureSettingsView`）。
- **Review 仪表盘**：按事件统计 token 的饼图、Top 5 高消耗记录、已删除累计 token、可配置预警阈值（`ReviewView`）。
- **主题**：Notiee 绿强调色与系统默认可选，菜单图标跟随强调色（`Utils/NotieeColors.swift`）。
- **场景预设**：四套预设一键切换解析策略。
- **实验室（Lab）**：Markdown 渲染、低消耗模式（端侧 OCR + ANE）、全视觉模式、深度关联模式、iCloud 手动同步、TMN 导入（`LabFeaturesView`）。
- **日程管理**：日历选择、课程日历标注、导入课表、过往/未来日程（`CalendarSelectionView`、`CourseCalendarSelectionView`、`ImportScheduleView`、`AllSchedulesView`、`PastSchedulesView`）。
- **关于 / 法务 / 开源致谢 / 更新日志**：`AboutNotieeView`、`PrivacyAgreementView`、`OpenSourceAcknowledgmentsView`、`WhatsNewView`、`PDFPreviewView`。

---

## 4. Spark AI 助手与 Agent

**Spark** 是 Notiee 内置的 AI 对话助手（底栏第四 Tab，目前标记 `beta`），既能普通问答，也能切换为 **Agent** 直接操作 App 数据。

### 4.1 对话层

- `SparkView` / `SparkViewModel`：聊天界面、消息流、动态背景（`SparkBackgroundView`）、输入栏（`SparkInputBar`）、气泡（`SparkChatBubble`）。
- **会话与历史**：`SparkConversationStore`、`SparkConversationRepository`、`SparkHistoryStore` / `SparkHistoryView` 管理多会话与历史记录。
- **长期记忆**：`SparkMemoryStore` / `SparkMemoryView`，Spark 可记住用户偏好与事实。
- **引用**：`SparkCitationRow` 展示回答引用的记录来源。
- **模型与思考强度**：`SparkModelPreferences` / `SparkModelChip` 支持 Spark 局部覆盖模型；思考强度由 `ModelThinkingPolicy` / `ThinkingCapability` 按 Provider 注入。
- **意图识别**：`SparkIntentDetector` 判断用户消息意图。
- 非 Agent 模式下，Spark 也能看到只读的"即将到来的日程"作为上下文。

### 4.2 Agent 层（工具调用）

位于 `Features/Spark/Agent/`，采用经典的"工具调用循环"：

- **`AgentExecutor`**：最多 **5 轮**迭代的 Reason-Act 循环；把工具以 OpenAI / Anthropic 两种 schema 暴露给模型，
  解析模型返回的 `toolCalls`，逐个执行并把结果回填进对话，直至模型给出最终回答或某工具要求终止。
- **`AgentToolRegistry`**：工具注册表，按信任等级过滤可用工具，并生成 OpenAI/Anthropic 的函数/工具 JSON Schema。
- **`AgentTrustManager`**：信任等级（`AgentTrustLevel`）决定 Agent 能调用哪些工具（读 vs 写权限分级）。
- **`AgentActionStore`**：持久化 Agent 执行过的动作记录。
- **`AgentToolPresentation`**：把工具调用过程友好地呈现到聊天时间线（`SparkAgentTimelineView`）。

**内置工具（`Features/Spark/Agent/Tools/`）**：

| 工具 | 能力 |
|---|---|
| `DateInfoTool` | 查询日期/星期/节气等信息 |
| `CalendarQueryTool` | 查询日程 |
| `ScheduleCreateTool` / `ScheduleUpdateTool` | 创建 / 更新日程 |
| `NoteSearchTool` | 检索笔记 |
| `NoteGetDetailTool` | 获取笔记详情 |
| `NoteCreateTool` / `NoteUpdateTool` | 创建 / 更新笔记 |
| `TodoListTool` / `TodoCreateTool` / `TodoCompleteTool` | 列出 / 创建 / 完成待办 |
| `MemoryManageTool` | 读写 Spark 长期记忆 |

> 工具协议见 `AgentToolProtocol.swift`，每个工具声明 `name` / `description` / `parametersSchema` / `permission`。

---

## 5. AI 处理流水线

拍照后，记录进入异步处理队列（`AIPipelineManager` + `Services/AIProcessingService.swift`）：

```
Capture → NoteRecord(.pending) → 入队
        → 阶段一：Vision LLM   OCR(含 LaTeX) + 100 字内核心摘要
        → 阶段二：Text  LLM    12 字小标题 + 要点/术语 + 待办抽取
        → applyAIResult → NoteRecord(.completed) + tokenUsage
```

- **服务实现**：`RealAIProcessingService`（真实 API）+ `MockAIProcessingService`（无 Key / 测试回退）。
  API 客户端 `AIAPIClient.swift`，Prompt 由 `AIPromptProvider.swift` 提供，兼容 OpenAI / Anthropic 协议。
- **处理状态**（`AIProcessingState`）：`pending` → `processing` → `completed` / `failed` / `deadLetter`。
- **异常与重试**：API 限频时指数退避；连续失败移入死信队列（dead letter），前端支持手动重试（`retryAIProcessing`）。
- **完全离线**：本地缓存，网络恢复后自动续传。
- **低消耗模式**：可走端侧 OCR（`LocalOCRService.swift`，Apple Neural Engine）减少云端 token 消耗。
- **触发时机**：受 `aiEnabled` 与 `autoProcessAfterCapture` 控制，`live()` 默认 `autoProcess = true`。

---

## 6. 数据模型

核心模型位于 `Notiee/Models/`：

| 模型 | 说明 |
|---|---|
| **`NoteRecord`** | 笔记记录主体：`eventID` / `folderID` / `capturedAt` / `localImagePaths` / `title` / `ocrText` / `summary` / `detailedContent` / `processingState` / `keyPoints` / `definitions` / `isFavorite` / `isDeleted` / `tokenUsage` / `aiRetryCount` / `deviceName` 等。 |
| **`KeyDefinition`** | 术语定义（`term` + `explanation`）。 |
| **`NoteTodo`** | 待办项（内容、完成态、截止、提醒、可关联记录）。 |
| **`ScheduledEvent`** | 日程/课程/会议事件。 |
| **`SpecialDayEvent`** | 节假日 / 节气 / 生日等特殊日。 |
| **`CustomFolder`** / **`EventTag`** | 自建文件夹 / 彩色标签。 |
| **`ScenePreset`** | 四种使用场景预设。 |
| **`AIModelConfiguration`** / **`AIProvider`** | AI 模型配置与服务商。 |
| **`ModelThinkingPolicy`** / **`ThinkingCapability`** | 模型"思考强度"策略与能力（按 Provider 注入 payload）。 |
| **`AIProcessingState`** (+`+UI`) | AI 处理状态机及其 UI 映射。 |
| **`UserProfile`** | 用户资料。 |
| **`AppTab`** | 一级 Tab 枚举。 |
| **`ScheduleActivityAttributes`** | Live Activity（灵动岛/锁屏）属性。 |
| **`TMNModels`** | `.tmn` 备份归档的数据结构。 |
| **`UIDevice+ModelName`** | 设备型号名工具扩展。 |

---

## 7. 状态管理与架构

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
```

- **Manager 职责**
  - `RecordManager`：记录与待办的 CRUD、查询（收藏/已删/今日/待处理）、token 统计、Top N、搜索。
  - `CalendarManager`：系统日历同步、当前事件命中、特殊日检测、周次格式化、忽略/恢复日历事件、Live Activity 开关。
  - `FolderTagManager`：自建文件夹与标签、事件↔标签映射。
  - `AIPipelineManager`：入队、重试、应用 AI 结果（通过 `AIPipelineRecordAccess` 反向访问 Store）。
- **持久化**：`JSONNoteRecordStore` / `JSONCustomFolderStore` / `JSONEventTagStore` / `JSONScheduledEventStore`（本地 JSON）；
  偏好走 `UserDefaultsAppSettingsStore`（键集中在 `Utils/UserDefaultsKeys.swift`）；密钥（API Key）加密存于 **Keychain**。
- **拍照匹配**：`ScheduleMatcher` 处理课表冲突/重叠（关联最近创建/更新的日程，可手动切换）。
- **两套初始化**：`NotieeStore.live(...)` 从磁盘加载真实数据；`NotieeStore.sample(...)` 提供预览/测试样例数据。

---

## 8. 技术栈与依赖

| 层 | 技术 |
|---|---|
| UI | 100% SwiftUI，系统毛玻璃材质，弹簧动画，SF Symbols |
| 状态 | `NotieeStore` + 四 Manager + Combine |
| 持久化 | 本地 JSON、UserDefaults、Keychain |
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

> PRD 中描述的云端后端（FastAPI + Redis + PostgreSQL）为产品愿景；
> 当前实现以**本地离线优先**为主，AI 能力通过用户自带的大模型 API 直连完成。

---

## 9. 目录结构

```text
Notiee/
├── App/
│   ├── NotieeApp.swift            # @main 入口
│   └── RootTabView.swift          # 四 Tab 布局 + Camera Control + .tmn 打开
├── Features/
│   ├── Today/                     # 今日控制中心
│   ├── Capture/                   # 极速相机
│   ├── Records/                   # 知识库 + 记录详情
│   ├── Settings/                  # 我、设置、登录、备份、Review、Lab、Spark 设置
│   └── Spark/                     # AI 助手
│       └── Agent/                 # Agent 执行器、注册表、信任、工具
│           └── Tools/             # 12 个 Agent 工具
├── Models/                        # 领域模型
├── Services/                      # 基础设施
│   ├── NotieeStore.swift          # 中心状态门面
│   ├── Managers/                  # RecordManager / CalendarManager / FolderTagManager / AIPipelineManager
│   ├── CameraManager.swift        # AVFoundation 会话
│   ├── CalendarService.swift      # EventKit + 特殊日检测
│   ├── ScheduleMatcher.swift      # 拍照→日程匹配
│   ├── RealAIProcessingService.swift / MockAIProcessingService.swift
│   ├── AIAPIClient.swift / AIPromptProvider.swift
│   ├── LocalOCRService.swift      # 端侧 OCR (ANE)
│   ├── LiveActivityManager.swift / NotificationManager.swift
│   ├── ICloudSyncService.swift / SyncQueue.swift / NetworkMonitor.swift
│   ├── TMNExportService.swift / TMNImportService.swift / RecordMigrator.swift
│   └── JSON*Store / *Store / AccountStore / SystemPermissionManager
├── Components/                    # 可复用视图（EventCard / RecordCard / TodoRow ...）
├── Utils/                         # NotieeColors / LottieView / Logger / GlassStyle / UserDefaultsKeys
├── en.lproj / zh-Hans.lproj / zh-Hant.lproj   # 本地化
NotieeWidget/                      # Widget + Live Activity（灵动岛/锁屏）
NotieeTests/                       # 28 个单元测试
docs/                              # 文档（含本 Wiki、PRD、技术文档、官网规划等）
```

---

## 10. 备份与同步

- **TMN 归档**：`.tmn` 是基于 ZIP 的备份归档（`ZIPFoundation`），全保真导出/导入记录（含图片、摘要、要点、待办）。
  - 导出：`TMNExportService`；导入：`TMNImportService`。
  - 通过 `onOpenURL` 直接打开 `.tmn` 文件，弹出 `TMNImportPreviewSheet` 预览后导入（`Features/Settings/TMNImportPreviewSheet.swift`）。
- **iCloud 同步**：`ICloudSyncService` + `SyncQueue` 提供手动 iCloud 同步（实验室功能）；CloudKit 自动同步在规划中。
- **网络监测**：`NetworkMonitor` 驱动离线缓存与恢复后重传。
- **迁移**：`RecordMigrator` 处理历史数据结构迁移。

---

## 11. 权限与隐私

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
- 法务文件随包内置（隐私政策 / 用户协议，含简繁英多语 PDF）。

---

## 12. 本地化

覆盖全部 UI 文案，三种语言：

- **English**（`en.lproj`）
- **简体中文**（`zh-Hans.lproj`）
- **繁體中文**（`zh-Hant.lproj`）

---

## 13. 构建与测试

环境要求：**iOS 18.0+ · Xcode 16.0+ · Swift 6.0+**

```bash
open Notiee.xcodeproj
# Cmd+R 运行，Cmd+U 运行测试
```

**测试**：`NotieeTests/` 含 28 个单元测试，覆盖 Store、各 Manager、ViewModel、
日程匹配（`ScheduleMatcherTests`）、AI Mock（`MockAIProcessingServiceTests`）、
Spark 与 Agent 工具（`Spark*Tests`、`*ToolTests`）、思考策略（`ModelThinkingPolicyTests`/`ThinkingCapabilityTests`）等。

---

<sub>本 Wiki 基于源码通读整理，反映当前实现（含 Spark AI 助手）。如与早期 README/PRD 表述不一致，以源码为准。</sub>
