<p align="center">
  <img src="Notiee-iOS.png" alt="Notiee Logo" width="128" height="128" />
</p>

<h1 align="center">Notiee</h1>
<h3 align="center">Capture with your camera, find it by asking</h3>
<h3 align="center">用相机来记、用问话来找的私人记忆库</h3>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/Platform-iOS%2018.0+-blue.svg" alt="Platform"></a>
  <a href="#"><img src="https://img.shields.io/badge/Swift-6.0+-orange.svg" alt="Swift"></a>
  <a href="#"><img src="https://img.shields.io/badge/Xcode-16.0+-blue.svg" alt="Xcode"></a>
  <a href="#"><img src="https://img.shields.io/badge/Version-1.0.6-green.svg" alt="Version"></a>
  <a href="#"><img src="https://img.shields.io/badge/License-Proprietary-red.svg" alt="License"></a>
</p>

<p align="center">
  <b>English</b> · <a href="#中文">中文</a>
</p>

---

## Overview · 概览

**Notiee** is an iOS-native SwiftUI app that turns your camera into a personal memory library: see something worth keeping — a whiteboard, a page, a receipt, a line of text — and just snap it. No typing, no tidying up on the spot.

The real value is *later*. Photos you dump into the camera roll usually vanish into a black hole; in Notiee, everything you capture is searchable and — more importantly — **askable**. Ask *"how did that reimbursement flow go again?"* and Notiee answers from your own captures, with a citation back to the original shot. Snapping is just the fastest way to feed it; capture is auto-OCR'd, summarized, and turned into to-dos in the background. Everything is **offline-first**. Ships as two editions — **Notiee** (free, backend-powered AI + Pro subscription) and **Notiee+** (one-time purchase, bring-your-own model key).

> **中文：** Notiee 是一款 iOS 原生 SwiftUI 应用——用相机来记、用问话来找的私人记忆库。看到想记的东西
> （白板、一页书、单据、一段话），拍下就好，不用当场整理。真正的价值在以后：拍进相册的照片往往石沉大海，
> 而在 Notiee 里，拍过的内容都能搜到、更能**直接开口问**，从自己拍过的东西里得到答案并溯源回原图。
> 拍照只是最省事的输入；拍完后台自动 OCR、生成摘要、抽取待办，整体**离线优先**。分两个版本：
> **Notiee**（免费，后端代付 AI + Pro 订阅）与 **Notiee+**（一次买断，自带模型 key）。
> AI 流水线在断网时缓存、联网后自动续跑。内置 **Notti** AI 助手可对你自己的拍记、日程与待办进行对话与操作。

---

## Features · 功能

| Feature · 功能 | Description · 描述 |
|---|---|
| **Today · 今日** | Live timeline with special days (holidays / solar terms / birthdays), to-dos, and daily records; color-coded tags and custom folders. · 日程时间轴 + 特殊日（节假日/节气/生日）+ 待办 + 今日记录，支持彩色标签与自建文件夹。 |
| **Snap · 拍记** | Dark immersive camera with zoom presets, flash, burst mode, and schedule-aware auto-categorization; seamless capture with no blocking dialogs. · 暗色沉浸式相机，缩放预设、闪光、连拍、日程感知自动归类；无阻断式弹窗的无缝连拍。 |
| **Records · 记录** | Full-text search across titles, AI summaries, and OCR; multi-level folders plus system folders (Favorites / Uncategorized / Today / Pending / Trash). · 标题/摘要/OCR 全文检索，多级文件夹 + 系统文件夹（收藏/未分类/今日/待处理/回收站）。 |
| **Record Detail · 记录详情** | Image viewer, AI summary, detailed content (Markdown), key points, term definitions, to-dos, related-note suggestions; long-press copy/share on all text. · 图片查看、AI 摘要、详细内容（Markdown）、要点、术语定义、待办、相关笔记推荐；全文长按复制/分享。 |
| **Notti · AI 助手** | In-app AI chat grounded in your notes with inline citations, encrypted local memory, and an **Agent** mode that calls 18 tools to operate notes / schedule / to-dos / memory. · 接地于拍记的 AI 对话（行内引用）、本地加密记忆，以及可调用 18 个工具操作笔记/日程/待办/记忆的 **Agent** 模式。 |
| **Review · 用量** | Token dashboard with per-event pie chart, Top-5 records, accumulated deleted tokens, configurable warning threshold. · token 仪表盘：按事件饼图、Top 5 记录、已删累计、可配置预警阈值。 |
| **Scene Presets · 场景预设** | Professional / College / High School / Creator — auto-tunes AI parsing, course mode, LaTeX, vision strategy. · 高效职场人 / 大学生·研究生 / 中学生 / 创作者·研究者，自动调整解析策略、课程模式、LaTeX、视觉策略。 |
| **Live Activities · 实时活动** | Dynamic Island & Lock Screen with real-time event progress and countdown. · 灵动岛 & 锁屏实时事件进度与倒计时。 |
| **AI Models · AI 模型** | Bring-your-own Text & Vision LLMs (OpenAI / Anthropic compatible), custom models, per-provider thinking effort, connection testing. · 自带文本/视觉大模型（兼容 OpenAI/Anthropic），自定义模型、按服务商思考强度、连接测试。 |
| **Lab Features · 实验室** | Markdown rendering, Low-Consumption Mode (on-device OCR + ANE), Full Vision Mode, Deep Association Mode, manual iCloud sync, TMN import. · Markdown 渲染、低消耗模式（端侧 OCR + ANE）、全视觉模式、深度关联模式、iCloud 手动同步、TMN 导入。 |
| **Backup & Restore · 备份恢复** | `.tmn` ZIP archive export/import with full fidelity (images, summaries, to-dos). · `.tmn` ZIP 归档全保真导出/导入（图片、摘要、待办）。 |
| **Theme · 主题** | Notiee green accent alongside system default; menu icons follow the accent; light/dark adaptive. · Notiee 绿强调色与系统默认可选，菜单图标跟随强调色，明暗自适应。 |
| **Localization · 本地化** | 530+ strings in **English**, **简体中文**, **繁體中文**. · 530+ 文案，覆盖英文 / 简体 / 繁体。 |

---

## Notti AI Assistant · Notti AI 助手

Notti is the fourth tab — an in-app AI companion that can both chat and **act**.

Notti 是底栏第四个 Tab —— 一个既能对话、又能**动手操作**的 App 内 AI 伴侣。

**Chat mode · 对话模式**
- Grounds answers in your captured notes and cites them inline as `[来源N]`, rendered as tappable citation cards. · 回答接地于你的拍记，行内以 `[来源N]` 引用并渲染为可点引用卡片。
- Local-first encrypted **memory** with hybrid Top-K recall, evidence/access reinforcement, lifecycle states, and confirmation for sensitive facts. · 本地优先的加密**记忆**：混合 Top-K 召回、证据/使用强化、生命周期管理与敏感事实确认。
- Multi-conversation history, per-Notti model override, and adjustable thinking effort. · 多会话历史、Notti 局部模型覆盖、可调思考强度。
- Read-only awareness of upcoming schedule for context. · 只读感知未来日程作为上下文。

**Agent mode · Agent 模式**
- A Reason–Act loop (up to 5 iterations) exposes tools to the model via OpenAI / Anthropic schemas. · Reason–Act 循环（最多 5 轮），以 OpenAI/Anthropic schema 把工具暴露给模型。
- A **trust manager** gates which tools are available (read vs. write). · **信任等级**控制可用工具（读 / 写）。
- 18 built-in tools cover dates, schedules, notes, to-dos, bounded memory search/forget, and web search/fetch. · 18 个内置工具覆盖日期、日程、笔记、待办、有界记忆检索/遗忘与网页搜索/读取。

> Note · 说明: Note and memory retrieval are both bounded. Notes use anchor + semantic recall; Notti memory combines local semantic, BM25, entity, and time signals before injecting only the ranked Top-K. · 笔记与记忆召回均有界：拍记使用锚点 + 语义召回，Notti 记忆在本地融合语义、BM25、实体和时间信号后只注入排序后的 Top-K。

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
│   └── RootTabView.swift              # 4 tabs: Today / Snap / Records / Notti
├── Features/
│   ├── Today/                         # Today dashboard (settings entry → MeView)
│   ├── Capture/                       # Camera + capture flow
│   ├── Records/                       # Record archive + detail
│   ├── Settings/                      # Me, settings, login, backup, Review, Lab, Notti settings
│   └── Notti/                         # AI assistant
│       └── Agent/                     # Executor, registry, trust, tools
│           └── Tools/                 # 18 agent tools
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

**v1.0.6** · two editions (Notiee / Notiee+) + backend-powered free tier · 双版本（Notiee / Notiee+）+ 免费版后端代付

- [x] **Two editions** — Notiee (free: self-hosted backend AI + Apple login + Pro subscription) / Notiee+ (one-time BYOK) · **双版本** —— Notiee（免费：自建后端代付 + Apple 登录 + Pro 订阅）/ Notiee+（一次买断 BYOK）
- [x] **Notti AI assistant** — chat with citations, long-term memory, history · **Notti AI 助手** —— 带引用对话、长期记忆、历史
- [x] **Notti Agent** — 18 tools, trust levels, 5-iteration reason-act loop · **Notti Agent** —— 18 工具、信任等级、5 轮循环
- [x] Per-Notti model override + per-provider thinking effort · Notti 局部模型覆盖 + 按服务商思考强度
- [x] Manager-based store architecture (Record / Calendar / FolderTag / AIPipeline) · 基于 Manager 的状态架构
- [x] Scene presets (Professional / College / High School / Creator) · 场景预设
- [x] Theme accent color, course-calendar marking, deep association mode · 主题强调色、课程日历标注、深度关联
- [x] Token consumption tracking (Top 5, deleted accumulation, per-record) · token 用量追踪
- [x] `.tmn` backup/restore · `.tmn` 备份恢复
- [x] Full localization (EN / 简体中文 / 繁體中文) · 全量本地化
- [ ] iCloud CloudKit auto-sync (planned) · iCloud 自动同步（规划中）
- [x] Bounded semantic/hybrid retrieval for notes and encrypted Notti memory · 拍记有界语义召回与 Notti 加密混合记忆召回

---

<a name="中文"></a>
<p align="center">
  <sub>Made for people who want to focus on learning, not organizing.</sub><br/>
  <sub>为想专注于学习、而非整理的人而做。</sub>
</p>
