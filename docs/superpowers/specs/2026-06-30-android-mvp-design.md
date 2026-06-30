# Notiee Android MVP Design Specification

## 1. 概述 (Overview)
Notiee 正在向 Android 平台进行移植。本次开发将聚焦于 MVP 版本（对应 iOS v1.0 核心能力），暂不包含 Spark AI 助手。Android 版本的核心目标是实现“日程感知”的极速拍记和基于大模型的知识提炼，同时确保应用在 Android 系统上的流畅度与原生体验。

## 2. 界面与交互策略 (UI/UX Strategy)
采用 **混合折中策略**：
*   **整体布局统一**：保持与 iOS 端一致的底部 3+1 导航结构（今日、拍记、记录、我）以及黑白/暗色调配色主题。
*   **控件原生化**：在具体系统交互控件上（如弹窗 Dialog、开关 Switch、底部抽屉 BottomSheet、返回手势等）采用 Android 默认的 Material Design 3 风格，以减少跨平台适配成本并迎合 Android 用户习惯。
*   **UI 框架**：100% 使用 **Jetpack Compose** 进行声明式 UI 开发。

## 3. 技术架构 (Technical Architecture)
全面拥抱现代 Android 推荐的架构模式，保证单向数据流与高可维护性。

*   **架构模式**：**MVI + Clean Architecture**
    *   **UI 层 (Presentation)**：Compose 渲染视图，ViewModel 管理状态 (StateFlow)。UI 通过发送 Intent 触发 ViewModel 状态变更。
    *   **领域层 (Domain)**：纯 Kotlin 实现，包含核心业务实体 (Model) 和 Use Cases (如 `MatchScheduleUseCase`, `ExtractTextUseCase`)，不依赖任何 Android 框架。
    *   **数据层 (Data)**：Repository 接口的实现，负责对接本地数据库 (Room) 和网络请求，实现离线优先。
*   **基础技术栈**：
    *   **语言**：Kotlin + Coroutines & Flow (异步处理)
    *   **依赖注入**：Hilt (Dagger)
    *   **网络通信**：Retrofit + OkHttp
    *   **图片加载**：Coil

## 4. 核心模块实现方案 (Core Modules)

### 4.1 Today (今日控制中心)
*   **日程同步**：使用 Android 的 `CalendarContract` ContentProvider 获取本地日历事件数据，适配 Android 权限请求。
*   **交互实现**：基于 Compose 的 `ModalBottomSheet` 实现下半部分今日动态展板的上滑展开效果。

### 4.2 拍记 (极速相机)
*   **相机框架**：集成 `CameraX`，确保在各类 Android 设备上的启动速度和拍照兼容性。
*   **后台流水线**：为实现“拍完即走”的无缝连拍，将图片存入本地缓存后，将 OCR 和摘要生成的任务推入 **WorkManager** 队列。即便应用被退到后台，系统也能保证 AI 任务可靠执行。

### 4.3 记录 (知识库)
*   **本地存储**：使用 **Room** 数据库作为应用的核心持久化层。
*   **全文搜索**：启用 Room 数据库的 **FTS4/FTS5 (Full Text Search)** 特性，对 AI 生成的摘要和底层 OCR 文本提供极速的本地关键词检索能力。

### 4.4 我 (设置与密钥)
*   **数据安全**：用户的 AI 大模型 API Key 等高度敏感信息，强制使用 Android 的 `EncryptedSharedPreferences` 结合 Keystore 进行硬件级别的安全加密存储。
*   **偏好设置**：常规设置使用 `DataStore (Preferences)` 存储。

## 5. 阶段外范围 (Out of Scope)
*   **Spark AI 助手及 Agent 模式**：推迟至二期进行开发。
*   **iOS 端“实验室”与“高级设置”中部分功能**：如 iCloud 同步、实时活动 (Live Activities) 等不属于本次 MVP Android 移植范畴。

## 6. 验证与后续步骤
本设计文档确立后，将进入具体实施计划的撰写阶段，随后将逐步搭建底层基础架构和各功能模块。
