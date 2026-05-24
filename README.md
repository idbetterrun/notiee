<p align="center">
  <img src="Notiee-iOS.png" alt="Notiee Logo" width="128" height="128" />
</p>

<h1 align="center">Notiee</h1>
<h3 align="center">📅 Schedule-Aware AI Rapid Note Capture</h3>
<h3 align="center">日程感知 AI 极速随手记</h3>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/Platform-iOS%2017.0+-blue.svg" alt="Platform"></a>
  <a href="#"><img src="https://img.shields.io/badge/Swift-5.9+-orange.svg" alt="Swift"></a>
  <a href="#"><img src="https://img.shields.io/badge/Xcode-15.0+-blue.svg" alt="Xcode"></a>
  <a href="#"><img src="https://img.shields.io/badge/Tests-28%20passed-success.svg" alt="Tests"></a>
  <a href="#"><img src="https://img.shields.io/badge/License-Proprietary-red.svg" alt="License"></a>
</p>

---

## 📖 Overview ｜ 概述

**Notiee** is an iOS-native (SwiftUI) rapid camera note-taking and AI knowledge extraction tool designed for students and professionals.

It solves the "easy to photograph, hard to organize" problem: by importing your calendar or class schedule, it automatically links each captured photo to the current course or meeting context. Meanwhile, an async AI pipeline performs OCR, generates 100‑word summaries, extracts precise titles, and builds structured to‑do lists — transforming scattered whiteboard photos into an organized knowledge stream.

**Notiee** 是一款专为学生和职场人打造的 iOS 原生 (SwiftUI) 极速相机随手记与 AI 知识提炼工具。

它彻底解决了"拍照容易整理难"的痛点：通过导入日历或课表，在你按下快门的瞬间，自动关联当前时间段的课程或会议上下文；同时通过异步队列调用 AI 大模型，自动对图片进行 OCR、生成 100 字摘要、提炼精准小标题和提取待办事项 (To‑do List)，将零散的课堂/会议板书照片无缝转化为结构化的知识流。

---

## ✨ Core Features ｜ 核心功能

| Feature 功能 | Description 说明 |
|---|---|
| **📅 Today 今日** | Today control center: highlights the active schedule in real time; vertically presents the day's timeline, to‑dos, and records. Supports **Event Tags** (color‑coded) and **Custom Folders** for efficient classification. 今日控制中心，高亮展示当前进行中的日程，纵向呈现今日时间轴、待办事项和今日记录。支持日程彩色标签与自建文件夹进行分类管理。 |
| **📷 Capture 拍记** | Immersive dark‑theme rapid burst camera. Zero blocking dialogs after capture; photos animate smoothly into a pending tray and auto‑bind to the current schedule. Fallback to "Uncategorized" when no active schedule. 暗色调沉浸式极速连拍体验。拍照后无阻断式弹窗，照片通过平滑动画飞入暂存区，并根据当前时间自动感知绑定日程。 |
| **📓 Records 记录** | Full‑text search across titles, summaries, and OCR text. Records archived by schedule and timeline, with custom folder hierarchy for flexible management. 支持全文字段精准检索（标题、摘要、OCR 原文）。按日程及时间线归档，支持自建文件夹多层级管理。 |
| **🏝️ Live Activities 灵动岛** | Real‑time Dynamic Island and Lock Screen display of the active schedule, progress, and countdown. 在 iOS 灵动岛及锁屏实时显示当前正在进行的日程、进度与倒计时。 |
| **👤 Me 我** | Configure your own Text LLM and Vision LLM providers (OpenAI‑compatible). API keys are encrypted and stored in the device **Keychain**, never in plain UserDefaults. 自主配置文本模型与图像识别模型，敏感 API Key 加密存储于本机 Keychain。 |
| **💾 Backup & Restore 备份还原** | Export and import via `.tmn` file format (ZIP‑based archive bundling all records, images, to‑dos, and schedules). Supports file‑based and URL scheme import. 通过 .tmn 文件格式（基于 ZIP 打包所有记录、图片、待办和日程）进行导出导入，支持文件与 URL Scheme 方式。 |
| **📋 TMN Import 课表导入** | Import class schedules from TMN‑format files; preview and selectively import events with tag support. 从 TMN 格式文件导入课表，支持预览和选择性导入带标签的日程事件。 |
| **🌐 Multi‑Language 多语言** | Full localization in **English**, **Simplified Chinese (zh‑Hans)**, and **Traditional Chinese (zh‑Hant)**. 完整的英、简中、繁中三语本地化。 |
| **🚀 Offline‑First 离线优先** | Full local save and fast retrieval even without internet. AI processing resumes automatically once connectivity returns. 支持完全无网环境下的本地保存与快速检索，网络恢复后自动异步处理。 |

---

## 🛠️ Tech Architecture ｜ 技术架构

The project follows an **Offline‑First** and **MVVM** architecture:

| Layer | Technology |
|---|---|
| **UI Framework** | 100% native SwiftUI; Apple HIG compliant; native blur materials, interactive sheets, fluid animations |
| **State Management** | `@MainActor` singleton `NotieeStore` with `@Published` properties, ensuring thread‑safe UI updates |
| **Data Persistence** | Local JSON serialization via `JSONNoteRecordStore`; settings via `UserDefaults` with Keychain‑backed secrets |
| **Camera** | AVFoundation native capture with zoom, flash control, and burst mode |
| **Calendar** | EventKit integration for reading system calendars |
| **AI Pipeline** | Async `Task`‑based queue calling OpenAI‑compatible APIs; `RealAIProcessingService` / `MockAIProcessingService` switchable |
| **Live Activities** | ActivityKit + `NotieeWidget` extension for Dynamic Island & Lock Screen |
| **Notifications** | `UserNotificationCenter` for schedule start/end alerts and Live Activity coordination |
| **Permissions** | Centralized `SystemPermissionManager` for camera, microphone, calendar, speech recognition, and photo library |

**Third‑Party Dependencies (Swift Package Manager):**

| Package | Version | Purpose |
|---|---|---|
| [NetworkImage](https://github.com/gonzalezreal/NetworkImage) | 6.0.1 | Async image loading with disk caching |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | 2.4.1 | Markdown rendering in SwiftUI |
| [swift-cmark](https://github.com/swiftlang/swift-cmark) | 0.8.0 | CommonMark parsing (dependency of markdown‑ui) |
| [OnboardingKit](https://github.com/danielsaidi/OnboardingKit) | main | Onboarding flow components |
| [PageView](https://github.com/danielsaidi/PageView) | 0.2.0 | Paged scroll views |
| [WhatsNewKit](https://github.com/SvenTiigi/WhatsNewKit) | main | "What's New" update screen |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 0.9.20 | .tmn archive compression/decompression |

---

## 📂 Project Structure ｜ 项目结构

```text
Notiee/
├── App/                              # App entry point & root routing
│   ├── NotieeApp.swift               #   @main — privacy → welcome → whatsnew → root tabs
│   └── RootTabView.swift             #   4-tab layout + TMN import handling
│
├── Features/                         # Core feature modules (28 Swift files)
│   ├── Today/                        #   Today dashboard (4 files)
│   │   ├── TodayView.swift           #     Timeline, to‑dos, records with collapsible sections
│   │   ├── TodayViewModel.swift      #     Filtering, sorting, grouping logic
│   │   ├── CreateItemSheet.swift     #     Create new records / to‑dos from Today
│   │   └── TagEditSheet.swift        #     Edit and assign event tags
│   │
│   ├── Capture/                      #   Schedule‑aware camera (4 files)
│   │   ├── CaptureView.swift         #     Immersive dark camera UI + pending tray
│   │   ├── CaptureViewModel.swift    #     Capture session & burst queue
│   │   ├── CameraPreviewView.swift   #     AVFoundation preview layer
│   │   └── NotieeCameraIntent.swift  #     Siri / Shortcuts camera intent
│   │
│   ├── Records/                      #   Knowledge archive (8 files)
│   │   ├── RecordsView.swift         #     Search, filter, folder browsing
│   │   ├── RecordDetailView.swift    #     Full record view: OCR, AI summary, to‑dos
│   │   ├── RecordDetailViewModel.swift
│   │   ├── RecordEditSheet.swift     #     Inline editing
│   │   ├── RecordThumbnailView.swift #     Grid / list thumbnails
│   │   ├── EventDetailView.swift     #     Schedule event drill‑down
│   │   ├── SwipeableTodoRow.swift    #     Swipe‑to‑complete to‑dos
│   │   └── HighlightedText.swift     #     Keyword highlighting in search results
│   │
│   └── Settings/                     #   "Me" page & app preferences (13 files)
│       ├── SettingsView.swift        #     Main settings hub
│       ├── SettingsViewModel.swift   #     Theme, font, language, AI config
│       ├── WelcomeView.swift         #     First‑run onboarding
│       ├── PrivacyAgreementView.swift#     Privacy consent gate
│       ├── WhatsNewView.swift        #     Version update changelog
│       ├── AboutNotieeView.swift     #     App info, credits, acknowledgements
│       ├── LabFeaturesView.swift     #     Experimental features toggle
│       ├── BackupRestoreView.swift   #     .tmn export & import
│       ├── ImportScheduleView.swift  #     TMN schedule import manager
│       ├── TMNImportPreviewSheet.swift
│       ├── EventImportPreviewSheet.swift
│       ├── PastSchedulesView.swift   #     Archived / past schedules
│       └── AllSchedulesView.swift    #     Full schedule browser
│
├── Models/                           # Domain models (13 files)
│   ├── NoteRecord.swift              #   Core record: images, OCR, summary, AI state
│   ├── NoteTodo.swift                #   To‑do item with completion tracking
│   ├── ScheduledEvent.swift          #   Calendar entry / class session
│   ├── EventTag.swift                #   Color‑coded event classification
│   ├── CustomFolder.swift            #   User‑defined folder hierarchy
│   ├── AppTab.swift                  #   Tab bar enumeration
│   ├── AIProvider.swift              #   AI service provider config
│   ├── AIModelConfiguration.swift    #   Model selection & parameters
│   ├── AIProcessingState.swift       #   AI pipeline state machine
│   ├── AIProcessingState+UI.swift    #   UI helpers for AI states
│   ├── TMNModels.swift               #   TMN schedule format models
│   ├── UIDevice+ModelName.swift      #   Device model string extension
│   └── ScheduleActivityAttributes.swift  # ActivityKit attributes
│
├── Services/                         # Infrastructure layer (20 files)
│   ├── NotieeStore.swift             #   @MainActor central data store
│   ├── JSONNoteRecordStore.swift     #   JSON file persistence
│   ├── ScheduledEventStore.swift     #   Schedule event storage
│   ├── EventTagStore.swift           #   Event tag CRUD
│   ├── CustomFolderStore.swift       #   Folder tree management
│   ├── CameraManager.swift           #   AVFoundation capture session
│   ├── LocalImageStore.swift         #   Local image file storage
│   ├── ImageSaver.swift              #   Save images to photo library
│   ├── CalendarService.swift         #   EventKit calendar reader
│   ├── ScheduleMatcher.swift         #   Time‑based schedule matching
│   ├── AIProcessingService.swift     #   AI queue coordinator
│   ├── AIAPIClient.swift             #   OpenAI‑compatible HTTP client
│   ├── RealAIProcessingService.swift #   Real AI provider integration
│   ├── MockAIProcessingService.swift #   Mock AI with simulated responses
│   ├── LiveActivityManager.swift     #   Dynamic Island manager
│   ├── NotificationManager.swift     #   Local notification scheduling
│   ├── SystemPermissionManager.swift #   Centralized permission requests
│   ├── UserDefaultsAppSettingsStore.swift # Settings persistence
│   ├── TMNImportService.swift        #   TMN file parser & importer
│   └── TMNExportService.swift        #   TMN archive builder & exporter
│
├── NotieeWidget/                     # Widget & Live Activity extension (7 files)
│   ├── NotieeWidgetBundle.swift      #   Widget bundle entry
│   ├── NotieeWidget.swift            #   Home screen widget
│   └── NotieeWidgetLiveActivity.swift#   Dynamic Island & Lock Screen UI
│
├── NotieeTests/                      # Unit test suite (8 test files, 28 tests)
│   ├── ProjectConfigurationTests.swift
│   ├── TodayViewModelTests.swift
│   ├── SettingsViewModelTests.swift
│   ├── CaptureViewModelTests.swift
│   ├── RecordDetailViewModelTests.swift
│   ├── NotieeStoreTests.swift
│   ├── MockAIProcessingServiceTests.swift
│   └── ScheduleMatcherTests.swift
│
└── Localization/                     # 3 language localizations
    ├── en.lproj/Localizable.strings
    ├── zh-Hans.lproj/Localizable.strings
    └── zh-Hant.lproj/Localizable.strings
```

---

## 🚦 Quick Start ｜ 快速开始

### Prerequisites ｜ 环境要求

- **iOS 18.0+**
- **Xcode 16.0+**
- **Swift 6.0+**

### Run & Test ｜ 运行与测试

1. Open the project in Xcode:
   ```bash
   open Notiee.xcodeproj
   ```

2. Select an iOS simulator (iPhone 15 or newer recommended).

3. Press `Cmd + R` to build and run.

4. Press `Cmd + U` to run the unit test suite (**28 test cases**, covering schedule matching, Today filtering, persistence, settings state, AI processing, and project configuration).

---

## 🔐 Permissions ｜ 权限说明

| Permission 权限 | Reason 用途 |
|---|---|
| **Camera 相机** | Capture photos of whiteboards, slides, and notes 拍摄板书、幻灯片和笔记 |
| **Microphone 麦克风** | Voice recording for notes 语音记录 |
| **Photo Library 相册** | Import existing images as records 导入已有图片 |
| **Calendar 日历** | Read system calendar for schedule matching 读取系统日历进行日程匹配 |
| **Speech Recognition 语音识别** | Convert speech to text records 将语音转为文本记录 |
| **Notifications 通知** | Schedule start/end alerts and Live Activity coordination 日程开始/结束提醒 |

All sensitive API keys are encrypted in the iOS **Keychain**. 所有敏感 API Key 均加密存储于 **Keychain**。

---

## 📅 Version Status ｜ 版本状态

**Current: v1.0 (MVP)**

- [x] Native SwiftUI interface with blur materials and dark mode
- [x] Intelligent schedule matching (`ScheduleMatcher`) and timeline logic
- [x] Local JSON record persistence with secure Keychain secrets
- [x] Full mock AI pipeline with smooth state transitions
- [x] Real AVFoundation camera with zoom, flash, and burst mode
- [x] iOS Live Activities (Dynamic Island & Lock Screen)
- [x] Custom folders and fine‑grained classification
- [x] Color‑coded Event Tags with dynamic editing
- [x] Real AI provider integration (OpenAI‑compatible) with mock fallback
- [x] `.tmn` file‑based backup, restore, and cross‑device migration
- [x] TMN schedule import with preview and selective import
- [x] Multi‑language support (EN, zh‑Hans, zh‑Hant)
- [x] Comprehensive unit test suite (28 tests)
- [ ] iCloud CloudKit multi‑device sync (under evaluation ｜ 评估中)

---

<p align="center">
  <sub>Made with ❤️ for students and professionals who want to focus on learning, not organizing.</sub>
</p>
