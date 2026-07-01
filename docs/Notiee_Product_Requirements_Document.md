# Notiee 产品需求文档 (PRD) 完整细节版（深入代码架构版）

## 1. 产品概述
**产品名称**：Notiee
**产品定位**：日程感知 AI 极速随手记（Schedule-Aware AI Rapid Note Capture）
**目标用户**：频繁需要记录板书、PPT、会议白板的学生和职场人士。
**平台支持**：iOS 18.0+ (100% SwiftUI 原生开发)
**核心思想**：彻底解决“拍照容易整理难”的痛点，主打极速无阻断连拍、基于大模型的知识提炼（OCR/摘要/待办），以及与系统深层集成的多端同步体验。

---

## 2. 核心功能与模块设计 (详尽拆解)

### 2.1 🚀 App 启动与系统集成 (App & Extensions)
* **首次引导与协议验证 (Onboarding & Privacy)**：
  * **WelcomeView & WhatsNewView**：应用启动的特性介绍，以及版本更新后的变更日志概览。
  * **PrivacyAgreementView & PDFPreviewView**：严格的隐私门禁。内置 PDF 预览组件支持直接渲染《用户协议》和《隐私政策》，确保用户授权。
* **iOS 18 专属深层交互**：
  * **NotieeCaptureExtension (Camera Control)**：深度集成 iOS 18 全新的 Camera Control 按钮特性，实现在锁屏状态下 (`LockedCaptureEntryView`) 盲按实体键一键直达极速拍记。
  * **Siri 快捷指令 (NotieeCameraIntent)**：支持用户通过 Siri 语音“用 Notiee 拍照”或“快捷指令”App 直接唤起拍摄流。
  * **灵动岛与锁屏实时活动 (Live Activities)**：基于 `ActivityKit`，当有日程正在进行时，灵动岛会呈现进度条与剩余时间；锁屏大卡片不解锁即可查看进度。
  * **桌面小组件 (Home Screen Widget)**：提供今日待办和日程概览卡片。

### 2.2 👤 账户与云端同步 (Login & iCloud Sync)
* **TomaGo 统一登录 (LoginView)**：
  * 支持通过原生生态体系登录：微信授权、Sign in with Apple、Google 账号授权。登录后解锁多端漫游与云备份。
* **苹果原生云备份 (ICloudSyncService)**：
  * 在 Ubiquity Container 中建立 `NotieeSync` 同步目录。
  * **机制**：在后台将每一条记录打包为独立的 `.tmn` 文件上传至 iCloud，并在新设备上调用 `downloadAndMerge` 与本地进行无冲突合并。解决多设备无缝衔接。

### 2.3 📅 今日控制中心 (Today)
* **日程时间轴 (Timeline & ScheduleMatcher)**：
  * 自动结合 `CalendarService` 抓取并匹配当天的系统日历与导入的课程。
  * **日程高亮**：正在进行的日程会以高亮卡片形态展示。
  * **特殊节日标记 (SpecialDayEvent)**：代码层级支持识别节日(Holiday, 红色)、生日(Birthday, 粉色)和节气(SolarTerm, 绿色)，并在时间轴中提供特殊的 UI 点缀。
* **彩色标签与自定义管理**：
  * **EventTag**：为不同的课程或会议指定彩色标签 (`TagEditSheet`) 方便视觉区分。
  * **快捷创建 (CreateItemSheet)**：无需拍照，直接输入文字创建灵感笔记或待办事项。
* **今日看盘**：可折叠面板直接浏览今天产生的所有记录与 To-do。

### 2.4 📷 极速拍记 (Capture)
* **沉浸式暗色相机 (CameraPreviewView)**：
  * 底层深度封装 `AVFoundation`，UI 采用极度纯粹的深色模式，提供双指缩放、闪光灯快捷控制。
* **智能优先级与课程筛选 (CourseCalendarSelectionView)**：
  * 用户可以在设置中将某些特定的系统日历标记为“我的课程”。
  * 拍摄时，属于这些“课程日历”的日程会在感知绑定的候选列表中**置顶优先显示**。
* **零阻断连拍体验 (Zero-Blocking)**：
  * 快门按下后，没有任何确认弹窗，图片顺滑落入左下角的暂存区。如果在没有日程的时间段，默认落入“未分类”。

### 2.5 📓 知识库与本地检索 (Records)
* **富文本知识详情 (RecordDetailView)**：
  * 展示本地存储的图片、由 AI 提炼的小标题、摘要（支持 Markdown 渲染）以及解析出的代办任务。
  * OCR 原文可折叠展开并支持一键复制。支持通过 `RecordEditSheet` 进行行内编辑。
* **全要素搜索与高亮 (HighlightedText)**：
  * 穿透检索图片 OCR 底层文字，通过 `HighlightedText` 将搜索命中词**自动高亮变红**。
* **分类与筛选层级**：
  * **CustomFolder**：用户可自建多层级的文件夹树。
  * **滑动待办 (SwipeableTodoRow)**：对提取出的 Action Items 进行左右滑动手势完成、删除。

### 2.6 ⚙️ 实验室功能与高级设定 (Lab Features & Settings)
这是 Notiee 面向极客与重度用户的专属“前沿阵地”，所有实验性功能均通过 `LabFeaturesView` 进行开关与配置：

* **1. 学生模式 (Student Mode)**：
  * 专为高校学生打造的学术增强模式。开启后不仅能关联“我的课程”，AI 还会对黑板或 PPT 照片进行**深入学术提炼**：自动提取核心“知识点”与“名词解释”，且所有数学/物理公式均强制使用 **LaTeX** 格式表达，并在详情页新增专属知识点卡片。
* **2. 全功能视觉模式 Beta (Full Vision Mode)**：
  * 突破传统单纯的文字 OCR 限制。开启后，视觉模型不仅提取文字，还会对照片中非文字信息（如物体、场景、图表、甚至板书绘制的示意图）进行全方位语义描述。
* **3. 深度联想模式 (Deep Association Mode)**：
  * 让原本孤立的笔记产生化学反应。开启后提供“笔记续篇检测”（同课程相邻时间的笔记自动提示关联合并），并在详情页底部提供“相关历史笔记推荐”，为未来的“知识图谱与语义搜索”打下基础。
* **4. Markdown 渲染开关**：
  * 允许在记录详情页支持渲染标准的 Markdown 语法（加粗、列表、区块等），提升文字排版美感。

### 2.7 📦 数据交换：TMN 专属格式 (.tmn)
**注意：`.tmn` 并非课表格式，而是专属的结构化笔记文件！**
* **定义与来源**：`.tmn` 是 Notiee 以及 TomaNotes 等关联笔记应用通用的私有结构化备份格式。
* **底层机制 (TMNModels & TMNExportService)**：
  * 基于 ZIP Foundation 打包。内部包含严谨的 JSON Manifest (如 `schema_version`, `encryption`, `ai_processing` 状态等) 以及多媒体附件。
  * 它可以无损携带一张照片的 OCR 原文、AI 提取的 100 字摘要、解析出来的待办事项 (To-dos) 以及绑定的日程上下文。
* **导入与导出**：
  * 在 `LabFeaturesView` 或全局拦截中均可导入 `.tmn`。
  * 导入时会经过 `TMNImportPreviewSheet` 进行解析和预览，用户确认后方可完整无损恢复至本地数据库，实现完全脱离云端的跨设备物理迁移。

### 2.8 自助大模型接入 (AI Configuration)
* 本地配置 OpenAI 兼容格式的模型端点与 API Key。架构支持分别配置用于图像理解的 Vision LLM 和用于文本梳理的 Text LLM。
* **数据安全**：Key 绝不存明文，由 iOS Keychain 硬件级加密接管。

---

## 3. 技术架构底层细节 

* **状态机设计 (AIProcessingState)**：
  * 处理流程严格遵循状态枚举：`pending` -> `uploading` -> `processing` -> `success/failed`，配合断网重连队列管理，保证“离线优先”。
* **数据持久层**：
  * 采用轻量级 JSON 存储架构 (`JSONNoteRecordStore`, `CustomFolderStore`)，规避 CoreData 的庞大迁移负担。
* **权限管理器 (SystemPermissionManager)**：
  * 将所有 iOS 权限收敛在统一单例中。

---
本需求文档已依据项目中的实际 Swift 代码逻辑与 `LabFeaturesView` 等特性彻底重构。
