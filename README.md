<p align="center">
  <img src="Notiee-iOS.png" alt="Notiee Logo" width="128" height="128" />
</p>

<h1 align="center">Notiee</h1>
<h3 align="center">Schedule-Aware AI Rapid Note Capture</h3>
<h3 align="center">日程感知 AI 极速拍记</h3>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/Platform-iOS%2018.0+-blue.svg" alt="Platform"></a>
  <a href="#"><img src="https://img.shields.io/badge/Swift-6.0+-orange.svg" alt="Swift"></a>
  <a href="#"><img src="https://img.shields.io/badge/Xcode-16.0+-blue.svg" alt="Xcode"></a>
  <a href="#"><img src="https://img.shields.io/badge/Version-1.0.3-green.svg" alt="Version"></a>
  <a href="#"><img src="https://img.shields.io/badge/License-Proprietary-red.svg" alt="License"></a>
</p>

<p align="center">
  <b>English</b> · <a href="#中文">中文</a>
</p>

---

## Overview · 概览

**Notiee** is an iOS-native SwiftUI app for rapid camera note-taking with AI-powered knowledge extraction. Designed for students and professionals.

Aim your camera at a whiteboard, lecture slide, or meeting note — Notiee auto-links it to your current calendar event, runs OCR, generates a summary, extracts key points, and builds a to-do list. Everything is **offline-first**, with an async AI pipeline that resumes when connectivity returns. The built-in **Spark** AI assistant lets you chat with — and act on — your own notes, schedule, and to-dos.

> **中文：** Notiee 是一款 iOS 原生 SwiftUI 应用，面向学生与职场人，用于极速拍照记录并由 AI 提炼知识。
> 举起相机对准白板、课件或会议笔记，Notiee 会自动把它关联到当前日程，完成 OCR、生成摘要、提炼要点并抽取待办。
> 整体**离线优先**，AI 流水线在断网时缓存、联网后自动续跑。内置 **Spark** AI 助手可对你自己的拍记、日程与待办进行对话与操作。

---

## Features · 功能

| Feature · 功能 | Description · 描述 |
|---|---|
| **Today · 今日** | Live timeline with special days (holidays / solar terms / birthdays), to-dos, and daily records; color-coded tags and custom folders. · 日程时间轴 + 特殊日（节假日/节气/生日）+ 待办 + 今日记录，支持彩色标签与自建文件夹。 |
| **Snap · 拍记** | Dark immersive camera with zoom presets, flash, burst mode, and schedule-aware auto-categorization; seamless capture with no blocking dialogs. · 暗色沉浸式相机，缩放预设、闪光、连拍、日程感知自动归类；无阻断式弹窗的无缝连拍。 |
| **Records · 记录** | Full-text search across titles, AI summaries, and OCR; multi-level folders plus system folders (Favorites / Uncategorized / Today / Pending / Trash). · 标题/摘要/OCR 全文检索，多级文件夹 + 系统文件夹（收藏/未分类/今日/待处理/回收站）。 |
| **Record Detail · 记录详情** | Image viewer, AI summary, detailed content (Markdown), key points, term definitions, to-dos, related-note suggestions; long-press copy/share on all text. · 图片查看、AI 摘要、详细内容（Markdown）、要点、术语定义、待办、相关笔记推荐；全文长按复制/分享。 |
| **Spark · AI 助手** | In-app AI chat grounded in your notes with inline citations, long-term memory, and an **Agent** mode that calls 12 tools to operate notes / schedule / to-dos. · 接地于拍记的 AI 对话（行内引用）、长期记忆，以及可调用 12 个工具操作笔记/日程/待办的 **Agent** 模式。 |
| **Review · 用量** | Token dashboard with per-event pie chart, Top-5 records, accumulated deleted tokens, configurable warning threshold. · token 仪表盘：按事件饼图、Top 5 记录、已删累计、可配置预警阈值。 |
| **Scene Presets · 场景预设** | Professional / College / High School / Creator — auto-tunes AI parsing, course mode, LaTeX, vision strategy. · 高效职场人 / 大学生·研究生 / 中学生 / 创作者·研究者，自动调整解析策略、课程模式、LaTeX、视觉策略。 |
| **Live Activities · 实时活动** | Dynamic Island & Lock Screen with real-time event progress and countdown. · 灵动岛 & 锁屏实时事件进度与倒计时。 |
| **AI Models · AI 模型** | Bring-your-own Text & Vision LLMs (OpenAI / Anthropic compatible), custom models, per-provider thinking effort, connection testing. · 自带文本/视觉大模型（兼容 OpenAI/Anthropic），自定义模型、按服务商思考强度、连接测试。 |
| **Lab Features · 实验室** | Markdown rendering, Low-Consumption Mode (on-device OCR + ANE), Full Vision Mode, Deep Association Mode, manual iCloud sync, TMN import. · Markdown 渲染、低消耗模式（端侧 OCR + ANE）、全视觉模式、深度关联模式、iCloud 手动同步、TMN 导入。 |
| **Backup & Restore · 备份恢复** | `.tmn` ZIP archive export/import with full fidelity (images, summaries, to-dos). · `.tmn` ZIP 归档全保真导出/导入（图片、摘要、待办）。 |
| **Theme · 主题** | Notiee green accent alongside system default; menu icons follow the accent; light/dark adaptive. · Notiee 绿强调色与系统默认可选，菜单图标跟随强调色，明暗自适应。 |
| **Localization · 本地化** | 530+ strings in **English**, **简体中文**, **繁體中文**. · 530+ 文案，覆盖英文 / 简体 / 繁体。 |

---

## Spark AI Assistant · Spark AI 助手

Spark is the fourth tab — an in-app AI companion that can both chat and **act**.

Spark 是底栏第四个 Tab —— 一个既能对话、又能**动手操作**的 App 内 AI 伴侣。

**Chat mode · 对话模式**
- Grounds answers in your captured notes and cites them inline as `[来源N]`, rendered as tappable citation cards. · 回答接地于你的拍记，行内以 `[来源N]` 引用并渲染为可点引用卡片。
- Long-term **memory** of your preferences and facts. · 关于你偏好与事实的长期**记忆**。
- Multi-conversation history, per-Spark model override, and adjustable thinking effort. · 多会话历史、Spark 局部模型覆盖、可调思考强度。
- Read-only awareness of upcoming schedule for context. · 只读感知未来日程作为上下文。

**Agent mode · Agent 模式**
- A Reason–Act loop (up to 5 iterations) exposes tools to the model via OpenAI / Anthropic schemas. · Reason–Act 循环（最多 5 轮），以 OpenAI/Anthropic schema 把工具暴露给模型。
- A **trust manager** gates which tools are available (read vs. write). · **信任等级**控制可用工具（读 / 写）。
- 12 built-in tools: date info, calendar query, schedule create/update, note search/get/create/update, todo list/create/complete, memory manage. · 12 个内置工具：日期信息、日程查询、日程增改、笔记搜/查/增/改、待办列/增/完成、记忆管理。

> Note · 说明: Note retrieval is keyword/lexical (title + summary + OCR substring match) or full-context injection — **not** vector/embedding RAG. · 笔记检索为关键词/词法匹配或全量上下文注入，**非**向量/嵌入式 RAG。

---

## Architecture · 架构

SwiftUI + MVVM with a central **`NotieeStore`** facade that composes four managers and mirrors their state via **Combine** for views to observe.

SwiftUI + MVVM，状态中心化在 **`NotieeStore`** 门面，它组合四个 Manager，并通过 **Combine** 把它们的状态镜像出来供视图订阅。

```text
                ┌─────────────────────────────┐
   Views ──────▶│        NotieeStore          │  @MainActor / @Published
                │  facade + Combine + delegate │
                └──┬────────┬────────┬───────┬─┘
                   │        │        │       │
           RecordManager  CalendarManager  FolderTagManager  AIPipelineManager
           records/todos  schedule/special  folders/tags     async AI queue
                   │
            ScheduleMatcher  (capture → event matching · 拍照→日程匹配)
```

| Manager | Responsibility · 职责 |
|---|---|
| `RecordManager` | Records & to-dos CRUD, queries, token stats, search. · 记录与待办 CRUD、查询、token 统计、搜索。 |
| `CalendarManager` | EventKit sync, current-event hit, special-day detection, Live Activity toggles. · 日历同步、当前事件命中、特殊日检测、Live Activity 开关。 |
| `FolderTagManager` | Custom folders & tags, event↔tag mapping. · 自建文件夹/标签、事件↔标签映射。 |
| `AIPipelineManager` | Enqueue / retry / apply AI results via `AIPipelineRecordAccess`. · 入队/重试/回填 AI 结果。 |

**Persistence · 持久化:** local JSON stores (`JSONNoteRecordStore`, `JSONScheduledEventStore`, …), `UserDefaults` for settings, **Keychain** for secrets (API keys). · 本地 JSON 存储、`UserDefaults` 偏好、**Keychain** 密钥（API Key）。

---

## AI Pipeline · AI 处理流水线

```text
Capture → NoteRecord(.pending) → enqueue
        → Stage 1  Vision LLM   OCR (incl. LaTeX) + short summary
        → Stage 2  Text  LLM    12-char title + key points + to-dos
        → applyAIResult → NoteRecord(.completed) + tokenUsage
```

- Implementations: `RealAIProcessingService` (live API) + `MockAIProcessingService` (no-key / test fallback); client `AIAPIClient`, prompts via `AIPromptProvider`. · 实现：`RealAIProcessingService` + `MockAIProcessingService` 回退；客户端 `AIAPIClient`，Prompt 由 `AIPromptProvider` 提供。
- States · 状态: `pending → processing → completed / failed / deadLetter`.
- Retry · 重试: exponential backoff; repeated failures go to a dead-letter queue with manual retry. · 指数退避；连续失败入死信队列，支持手动重试。
- Offline · 离线: cached locally, auto-resumed on reconnect. Low-Consumption Mode uses on-device OCR (`LocalOCRService`, ANE). · 本地缓存、联网续跑；低消耗模式走端侧 OCR（ANE）。

---

## Tech Stack · 技术栈

| Layer · 层 | Technology · 技术 |
|---|---|
| UI | 100% SwiftUI, native blur materials, spring animations, SF Symbols |
| State · 状态 | `NotieeStore` + 4 managers + Combine |
| Persistence · 持久化 | Local JSON · UserDefaults · Keychain |
| Camera · 相机 | AVFoundation (zoom presets, flash, burst, iOS 18 Camera Control) |
| Calendar · 日历 | EventKit (holiday / birthday / solar-term detection, course-calendar marking) |
| AI | Async `Task` queue, OpenAI / Anthropic compatible APIs |
| On-device OCR · 端侧 OCR | Vision / Apple Neural Engine (`LocalOCRService`) |
| Live Activities · 实时活动 | ActivityKit + Widget extension |
| Notifications · 通知 | `UNUserNotificationCenter` |
| Permissions · 权限 | Centralized `SystemPermissionManager` |

**Dependencies (Swift Package Manager) · 依赖:**

| Package | Purpose · 用途 |
|---|---|
| [lottie-ios](https://github.com/airbnb/lottie-ios) | Lottie animation rendering · Lottie 动画 |
| [NetworkImage](https://github.com/gonzalezreal/NetworkImage) | Async image loading + disk cache · 异步图片加载/缓存 |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown rendering · Markdown 渲染 |
| [swift-cmark](https://github.com/swiftlang/swift-cmark) | CommonMark parsing · CommonMark 解析 |
| [OnboardingKit](https://github.com/danielsaidi/OnboardingKit) | Onboarding flow · 新手引导 |
| [PageView](https://github.com/danielsaidi/PageView) | Paged scroll views · 分页滚动 |
| [WhatsNewKit](https://github.com/SvenTiigi/WhatsNewKit) | Version changelog · 更新日志 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | `.tmn` archive compression · TMN 归档压缩 |

---

## Project Structure · 项目结构

```text
Notiee/
├── App/
│   ├── NotieeApp.swift                # @main entry · 入口
│   └── RootTabView.swift              # 4 tabs: Today / Snap / Records / Spark
├── Features/
│   ├── Today/                         # Today dashboard (settings entry → MeView)
│   ├── Capture/                       # Camera + capture flow
│   ├── Records/                       # Record archive + detail
│   ├── Settings/                      # Me, settings, login, backup, Review, Lab, Spark settings
│   └── Spark/                         # AI assistant
│       └── Agent/                     # Executor, registry, trust, tools
│           └── Tools/                 # 12 agent tools
├── Models/                            # Domain models (NoteRecord, ScheduledEvent, ScenePreset, …)
├── Services/                          # Infrastructure
│   ├── NotieeStore.swift              # Central facade
│   ├── Managers/                      # RecordManager / CalendarManager / FolderTagManager / AIPipelineManager
│   ├── CameraManager.swift            # AVFoundation session
│   ├── CalendarService.swift          # EventKit + special-day detection
│   ├── ScheduleMatcher.swift          # Capture → event matching
│   ├── RealAIProcessingService.swift  # Live AI · MockAIProcessingService.swift fallback
│   ├── AIAPIClient.swift / AIPromptProvider.swift
│   ├── LocalOCRService.swift          # On-device OCR (ANE)
│   ├── LiveActivityManager.swift / NotificationManager.swift
│   ├── ICloudSyncService.swift / SyncQueue.swift / NetworkMonitor.swift
│   ├── TMNExportService.swift / TMNImportService.swift / RecordMigrator.swift
│   └── JSON*Store / AccountStore / SystemPermissionManager
├── Components/                        # Reusable views (EventCard / RecordCard / TodoRow …)
├── Utils/                             # NotieeColors / LottieView / Logger / GlassStyle / UserDefaultsKeys
├── en.lproj / zh-Hans.lproj / zh-Hant.lproj   # Localization (530+ strings)
NotieeWidget/                          # Widget + Live Activity
NotieeTests/                           # 28 unit-test files
docs/                                  # Docs (Wiki, PRD, tech doc, …)
```

---

## Quick Start · 快速开始

**iOS 18.0+** · **Xcode 16.0+** · **Swift 6.0+**

```bash
open Notiee.xcodeproj
# Cmd+R to run · 运行    Cmd+U to test · 测试
```

To use AI features, add your own Text & Vision model API keys under **Me → AI** (stored in Keychain). · 使用 AI 功能需在「我 → AI」中填入自带的文本/视觉模型 API Key（存于 Keychain）。

---

## Permissions · 权限

| Permission · 权限 | Purpose · 用途 |
|---|---|
| Camera · 相机 | Capture whiteboard / notes photos · 拍摄白板/笔记照片 |
| Microphone · 麦克风 | Voice recording · 语音录制 |
| Photo Library · 相册 | Import existing images · 导入已有图片 |
| Calendar · 日历 | Read system calendar for schedule matching · 读取日历进行日程匹配 |
| Speech Recognition · 语音识别 | Voice-to-text · 语音转文字 |
| Notifications · 通知 | Event start/end alerts · 事件开始/结束提醒 |

API keys are encrypted in the iOS **Keychain** and never leave the device. · API Key 加密存于 iOS **Keychain**，不离开设备。

---

## Backup & Sync · 备份与同步

- **TMN archive · TMN 归档:** `.tmn` is a ZIP-based, full-fidelity export/import (`TMNExportService` / `TMNImportService`); opening a `.tmn` file shows an import-preview sheet. · `.tmn` 为基于 ZIP 的全保真导出/导入，打开 `.tmn` 弹出导入预览。
- **iCloud:** manual sync via `ICloudSyncService` + `SyncQueue` (Lab feature); automatic CloudKit sync planned. · `ICloudSyncService` + `SyncQueue` 手动同步（实验室），自动 CloudKit 同步规划中。
- **Network · 网络:** `NetworkMonitor` drives offline caching and resume-on-reconnect. · `NetworkMonitor` 驱动离线缓存与联网续传。

---

## Version & Recent Updates · 版本与近期更新

**v1.0.3** + ongoing Spark integration · 持续集成 Spark

- [x] **Spark AI assistant** — chat with citations, long-term memory, history · **Spark AI 助手** —— 带引用对话、长期记忆、历史
- [x] **Spark Agent** — 12 tools, trust levels, 5-iteration reason-act loop · **Spark Agent** —— 12 工具、信任等级、5 轮循环
- [x] Per-Spark model override + per-provider thinking effort · Spark 局部模型覆盖 + 按服务商思考强度
- [x] Manager-based store architecture (Record / Calendar / FolderTag / AIPipeline) · 基于 Manager 的状态架构
- [x] Scene presets (Professional / College / High School / Creator) · 场景预设
- [x] Theme accent color, course-calendar marking, deep association mode · 主题强调色、课程日历标注、深度关联
- [x] Token consumption tracking (Top 5, deleted accumulation, per-record) · token 用量追踪
- [x] `.tmn` backup/restore · `.tmn` 备份恢复
- [x] Full localization (EN / 简体中文 / 繁體中文) · 全量本地化
- [ ] iCloud CloudKit auto-sync (planned) · iCloud 自动同步（规划中）
- [ ] Semantic (vector) retrieval for Spark (planned) · Spark 语义向量检索（规划中）

---

<a name="中文"></a>
<p align="center">
  <sub>Made for people who want to focus on learning, not organizing.</sub><br/>
  <sub>为想专注于学习、而非整理的人而做。</sub>
</p>
