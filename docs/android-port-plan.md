# Notiee Android 原生移植方案

> 版本: 1.0 | 日期: 2026-05-24 | 基于 iOS v1.0.1 (MVP)

---

## 一、概述

### 1.1 项目定位

Notiee 是一款**日程感知的 AI 极速随手记**应用，核心价值链路：

```
拍照 → 自动关联当前日程 → AI 提取 OCR/摘要/标题/待办 → 本地归档
```

### 1.2 现有 iOS 项目概览

| 维度 | iOS 现状 |
|------|---------|
| 语言 | Swift 5.9+ / Swift 6.0 |
| UI 框架 | SwiftUI (100% 原生) |
| 架构 | MVVM，`@MainActor` 单例 `NotieeStore` |
| 持久化 | JSON 文件存储 + Keychain |
| 依赖管理 | Swift Package Manager (7 个依赖) |
| 最低系统 | iOS 18.0+ |
| 代码量 | ~60+ Swift 文件，~7000+ 行 |
| 测试 | 28 个单元测试用例 |
| 本地化 | en / zh-Hans / zh-Hant 三语 |

### 1.3 Android 移植目标

- **功能完全对齐**：iOS v1.0.1 所有功能在 Android 上完整实现
- **架构独立**：原生 Kotlin + Jetpack Compose，不引入跨平台框架
- **数据互通**：`.tmn` 文件格式完全兼容，双端可互导入导出
- **体验一致**：遵循 Material Design 3 规范，保持与 iOS 版一致的交互逻辑
- **最低系统**：Android 10 (API 29)，目标 Android 15 (API 35)

---

## 二、技术栈选型

### 2.1 核心技术栈

| 层次 | 技术 | 说明 |
|------|------|------|
| **语言** | Kotlin 2.1+ | 与 Swift 同为现代静态语言，协程对标 async/await |
| **UI 框架** | Jetpack Compose + Material 3 | 声明式 UI，对标 SwiftUI |
| **架构** | MVVM + Repository 模式 | 保持与 iOS 端相同分层 |
| **DI** | Hilt (Dagger) | 对标 Swift 的协议注入 |
| **持久化** | Room (SQLite) | 替代 JSON 文件存储，类型安全 |
| **加密存储** | EncryptedSharedPreferences + Android Keystore | 对标 iOS Keychain |
| **异步** | Kotlin Coroutines + Flow | 对标 Swift Concurrency + Combine |
| **图片加载** | Coil | 对标 NetworkImage |
| **导航** | Navigation Compose (Type-safe) | 对标 NavigationStack |
| **构建系统** | Gradle KTS + Version Catalog | 现代化依赖管理 |
| **最低 SDK** | API 29 (Android 10) | 覆盖 95%+ 设备 |
| **目标 SDK** | API 35 (Android 15) | 最新稳定版 |

### 2.2 第三方依赖清单

#### 官方库 (AndroidX / Jetpack)

| 依赖 | 版本 | 用途 |
|------|------|------|
| `androidx.compose.material3` | 1.4+ | Material Design 3 UI 组件 |
| `androidx.compose.ui` | 1.8+ | Compose 核心 |
| `androidx.navigation:navigation-compose` | 2.9+ | 类型安全的声明式导航 |
| `androidx.lifecycle:lifecycle-viewmodel-compose` | 2.9+ | ViewModel 集成 Compose |
| `androidx.datastore:datastore-preferences` | 1.1+ | 用户偏好存储（替代 UserDefaults） |
| `androidx.room:room-runtime` + `room-ktx` + `room-compiler` | 2.7+ | 类型安全的本地数据库 |
| `androidx.hilt:hilt-work` + `hilt-navigation-compose` | 1.2+ | Hilt DI 集成 |
| `androidx.camera:camera-camera2` + `camera-lifecycle` + `camera-view` | 1.4+ | 相机模块（替代 AVFoundation） |
| `androidx.work:work-runtime-ktx` | 2.10+ | 后台任务调度（替代 BGTask） |
| `androidx.security:security-crypto` | 1.1+ | 加密存储 |
| `androidx.glance:glance-appwidget` | 1.1+ | 桌面小组件（替代 WidgetKit） |
| `androidx.core:core-splashscreen` | 1.0+ | 启动画面 |

#### 第三方库

| 依赖 | 版本 | 用途 | iOS 对标 |
|------|------|------|---------|
| `io.coil-kt:coil-compose` | 2.7+ | 异步图片加载 | NetworkImage |
| `com.google.dagger:hilt-android` | 2.53+ | 依赖注入框架 | SPM 协议注入 |
| `com.squareup.okhttp3:okhttp` | 4.12+ | HTTP 客户端 | URLSession |
| `com.squareup.moshi:moshi-kotlin` + `moshi-kotlin-codegen` | 1.15+ | JSON 解析（AI API 响应） | Codable |
| `com.github.bumptech.glide:compose` | 1.0+ | Glide 集成 Compose（缩略图优化） | — |
| `com.airbnb.android:lottie-compose` | 6.6+ | 动画（引导页/加载状态） | Lottie iOS |
| `com.google.accompanist:accompanist-permissions` | 0.36+ | 运行时权限简化 | — |
| `com.mikepenz:aboutlibraries-compose-m3` | 11+ | 开源许可展示 | 自建 |
| `com.github.chrisbanes:PhotoView` | 2.3+ | 图片双指缩放查看 | 自建 FullScreenImageView |

---

## 三、架构设计

### 3.1 整体分层

```
┌─────────────────────────────────────────────────┐
│                    UI Layer                       │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐│
│  │  Today   │ │ Capture  │ │ Records  │ │ Me   ││
│  │  Screen  │ │  Screen  │ │  Screen  │ │Screen││
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └──┬───┘│
│       │ Compose     │            │           │     │
├───────┴─────────────┴────────────┴───────────┴─────┤
│                 ViewModel Layer                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────┐  │
│  │ TodayVM  │ │CaptureVM │ │RecordsVM │ │MeVM  │  │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └──┬───┘  │
│       └──────────────┴────────────┴──────────┘      │
│                        │                            │
├────────────────────────┼────────────────────────────┤
│              Domain / Model Layer                   │
│  NoteRecord, EventTag, ScheduledEvent,              │
│  NoteTodo, CustomFolder, AIProvider, etc.           │
├────────────────────────┼────────────────────────────┤
│              Repository Layer                       │
│  ┌───────────────┐ ┌──────────────┐ ┌───────────┐  │
│  │ NoteRepository│ │EventRepository│ │...        │  │
│  └───────┬───────┘ └──────┬───────┘ └─────┬─────┘  │
│          └────────────────┴───────────────┘         │
│                        │                            │
├────────────────────────┼────────────────────────────┤
│                Data Source Layer                    │
│  ┌────────┐ ┌─────────┐ ┌─────────┐ ┌───────────┐  │
│  │  Room  │ │DataStore│ │Encrypted│ │  CameraX   │  │
│  │(SQLite)│ │(Prefs)  │ │  Prefs  │ │  (Camera)  │  │
│  └────────┘ └─────────┘ └─────────┘ └───────────┘  │
└─────────────────────────────────────────────────────┘
```

### 3.2 核心设计原则

1. **单一数据源 (Single Source of Truth)**
   - `MainStore` (对标 `NotieeStore`) 作为唯一状态持有者
   - 所有 Repository 通过 Flow 暴露数据变更
   - ViewModel 通过 `collectAsState()` 驱动 UI

2. **离线优先**
   - Room 作为主数据源，所有写操作先落库
   - AI 处理结果写库后再通知 UI 刷新
   - `.tmn` 导入导出不依赖网络

3. **协议驱动（接口隔离）**
   - 每个 Repository 定义接口（对标 iOS 的 `*Persisting` 协议）
   - 方便单元测试 mock、未来切换实现

4. **协程 + Flow 端到端**
   - 对标 iOS `async/await` + `@Published` + Combine
   - 所有异步操作通过 `viewModelScope` 管理生命周期

---

## 四、模块设计

### 4.1 模块划分

```
app/                          # 应用主模块
├── di/                       # Hilt DI 模块
│   ├── AppModule.kt          # 全局单例（MainStore, repositories）
│   ├── DatabaseModule.kt     # Room 数据库
│   └── ServiceModule.kt      # AI 服务、相机等
│
├── data/                     # 数据层
│   ├── local/                # 本地数据源
│   │   ├── db/
│   │   │   ├── NotieeDatabase.kt          # Room 数据库
│   │   │   ├── dao/
│   │   │   │   ├── NoteRecordDao.kt
│   │   │   │   ├── TodoDao.kt
│   │   │   │   ├── ScheduledEventDao.kt
│   │   │   │   ├── EventTagDao.kt
│   │   │   │   └── CustomFolderDao.kt
│   │   │   ├── entity/
│   │   │   │   ├── NoteRecordEntity.kt
│   │   │   │   ├── TodoEntity.kt
│   │   │   │   ├── ScheduledEventEntity.kt
│   │   │   │   ├── EventTagEntity.kt
│   │   │   │   └── CustomFolderEntity.kt
│   │   │   └── converter/
│   │   │       └── Converters.kt          # TypeConverters (Date, UUID, List<String>)
│   │   ├── datastore/
│   │   │   └── SettingsDataStore.kt       # 用户偏好
│   │   ├── keystore/
│   │   │   └── SecureKeyStore.kt          # API Key 加密存储
│   │   └── image/
│   │       └── LocalImageStore.kt         # 本地图片文件管理
│   │
│   ├── repository/           # Repository 实现
│   │   ├── NoteRepositoryImpl.kt
│   │   ├── TodoRepositoryImpl.kt
│   │   ├── EventRepositoryImpl.kt
│   │   ├── TagRepositoryImpl.kt
│   │   └── FolderRepositoryImpl.kt
│   │
│   └── model/                # DTO / API 模型
│       ├── AiApiModels.kt    # OpenAI/Anthropic API 请求/响应
│       └── TmnModels.kt      # TMN 格式的 Moshi 模型
│
├── domain/                   # 领域层
│   ├── model/                # 领域模型
│   │   ├── NoteRecord.kt
│   │   ├── NoteTodo.kt
│   │   ├── ScheduledEvent.kt
│   │   ├── EventTag.kt
│   │   ├── CustomFolder.kt
│   │   ├── AIProvider.kt
│   │   ├── AIModelConfiguration.kt
│   │   ├── AIProcessingState.kt
│   │   ├── AppTab.kt
│   │   └── SpecialDayEvent.kt
│   │
│   ├── repository/           # Repository 接口（对标 *Persisting 协议）
│   │   ├── NoteRecordRepository.kt
│   │   ├── TodoRepository.kt
│   │   ├── ScheduledEventRepository.kt
│   │   ├── EventTagRepository.kt
│   │   ├── CustomFolderRepository.kt
│   │   └── SettingsRepository.kt
│   │
│   └── service/              # 服务接口
│   │   ├── AIProcessingService.kt   # 协议
│   │   ├── CalendarService.kt       # 协议
│   │   ├── ScheduleMatcher.kt       # 纯函数
│   │   └── TmnService.kt            # 协议
│   │
│   └── usecase/              # 可选：复杂业务用例
│       ├── CapturePhotoUseCase.kt
│       ├── ProcessRecordUseCase.kt
│       └── ImportScheduleUseCase.kt
│
├── ui/                       # UI 层
│   ├── MainStore.kt          # @Singleton 全局状态持有者（对标 NotieeStore）
│   ├── MainActivity.kt       # 入口 Activity
│   ├── RootScreen.kt         # 4-tab 底部导航（对标 RootTabView）
│   │
│   ├── navigation/
│   │   └── NotieeNavGraph.kt # 全局导航图
│   │
│   ├── theme/
│   │   ├── Theme.kt          # Material 3 主题（亮/暗/跟随系统）
│   │   ├── Color.kt          # 色板定义
│   │   └── Typography.kt     # 字体大小（small/medium/large/extraLarge）
│   │
│   ├── today/                # 今日页面
│   │   ├── TodayScreen.kt        # 日程时间线 + 待办列表
│   │   ├── TodayViewModel.kt
│   │   ├── components/
│   │   │   ├── EventCard.kt
│   │   │   ├── TimelineSection.kt
│   │   │   ├── RecordCard.kt
│   │   │   ├── TodoDetailSheet.kt
│   │   │   └── EventDetailSheet.kt
│   │   └── sheets/
│   │       ├── CreateItemSheet.kt     # 创建日程/待办
│   │       └── TagEditSheet.kt        # 编辑标签
│   │
│   ├── capture/              # 拍照页面
│   │   ├── CaptureScreen.kt
│   │   ├── CaptureViewModel.kt
│   │   └── components/
│   │       ├── CameraPreview.kt       # CameraX PreviewView 封装
│   │       ├── ShutterButton.kt
│   │       ├── CaptureModeSwitcher.kt
│   │       └── BatchThumbnailStrip.kt
│   │
│   ├── records/              # 记录页面
│   │   ├── RecordsScreen.kt
│   │   ├── RecordsViewModel.kt
│   │   ├── detail/
│   │   │   ├── RecordDetailScreen.kt
│   │   │   ├── RecordDetailViewModel.kt
│   │   │   ├── components/
│   │   │   │   ├── ImageCarousel.kt        # 图片轮播
│   │   │   │   ├── FullScreenImageView.kt   # 全屏图片查看
│   │   │   │   ├── CollapsibleSection.kt    # 可折叠区域
│   │   │   │   ├── SwipeableTodoRow.kt     # 滑动待办行
│   │   │   │   └── MarkdownContent.kt      # Markdown 渲染组件
│   │   │   └── sheets/
│   │   │       └── RecordEditSheet.kt
│   │   └── components/
│   │       ├── FolderListRow.kt
│   │       ├── RecordListRow.kt
│   │       ├── RecordThumbnail.kt
│   │       ├── HighlightedText.kt
│   │       └── EventDetailView.kt
│   │
│   ├── settings/             # 我的页面
│   │   ├── SettingsScreen.kt
│   │   ├── SettingsViewModel.kt
│   │   ├── onboarding/
│   │   │   ├── PrivacyAgreementScreen.kt
│   │   │   ├── WelcomeScreen.kt
│   │   │   └── WhatsNewScreen.kt
│   │   ├── subpages/
│   │   │   ├── AllSchedulesScreen.kt
│   │   │   ├── PastSchedulesScreen.kt
│   │   │   ├── ImportScheduleScreen.kt
│   │   │   ├── ReviewScreen.kt          # Token 用量统计
│   │   │   ├── BackupRestoreScreen.kt
│   │   │   ├── LabFeaturesScreen.kt
│   │   │   ├── AboutNotieeScreen.kt
│   │   │   ├── AIConfigurationScreen.kt
│   │   │   └── CustomModelsScreen.kt
│   │   └── components/
│   │       ├── SettingsRow.kt
│   │       └── AIConnectionTestRow.kt
│   │
│   └── common/               # 公共 UI 组件
│       ├── LoadingOverlay.kt
│       ├── EmptyStateView.kt
│       ├── ConfirmationDialog.kt
│       └── ShareSheet.kt
│
├── service/                  # 服务实现
│   ├── ai/
│   │   ├── RealAIProcessor.kt          # 对标 RealAIProcessingService
│   │   ├── MockAIProcessor.kt           # 对标 MockAIProcessingService
│   │   └── AIClient.kt                  # OkHttp 封装，支持 OpenAI + Anthropic
│   ├── calendar/
│   │   ├── AndroidCalendarService.kt    # ContentResolver 日历读取
│   │   └── ScheduleMatcherImpl.kt       # 时间匹配逻辑
│   ├── camera/
│   │   └── CameraManager.kt             # CameraX 封装
│   ├── notification/
│   │   ├── NotificationHelper.kt        # 通知渠道 + 发送
│   │   └── BootReceiver.kt             # 重启后恢复通知调度
│   ├── widget/
│   │   └── NotieeWidgetProvider.kt      # Glance 小组件
│   ├── tmn/
│   │   ├── TmnImporter.kt              # TMN 导入
│   │   ├── TmnExporter.kt              # TMN 导出
│   │   └── TmnValidator.kt             # 格式校验
│   ├── permission/
│   │   └── PermissionManager.kt         # 集中权限管理
│   └── schedule/
│       └── ScheduleNotificationWorker.kt  # WorkManager 日程提醒
│
├── util/
│   ├── DateExtensions.kt
│   ├── ColorExtensions.kt               # Hex → Color
│   ├── FileExtensions.kt
│   └── DeviceInfoUtil.kt               # 设备型号获取
│
├── res/                       # 资源文件
│   ├── values/
│   │   ├── strings.xml        # 英文字符串（对标 en.lproj）
│   │   ├── themes.xml
│   │   └── colors.xml
│   ├── values-zh-rCN/
│   │   └── strings.xml        # 简体中文（对标 zh-Hans.lproj）
│   └── values-zh-rTW/
│       └── strings.xml        # 繁体中文（对标 zh-Hant.lproj）
│
└── NotieeApplication.kt       # Application 类（Hilt 入口）
```

### 4.2 widget/ 模块（独立 Gradle 模块）

```
widget/
├── build.gradle.kts           # 独立模块（需要在 AndroidManifest 声明为 widget）
├── src/main/
│   ├── AndroidManifest.xml
│   ├── kotlin/.../
│   │   └── NotieeWidgetProvider.kt   # GlanceAppWidget + GlanceAppWidgetReceiver
│   └── res/
│       └── xml/
│           └── notiee_widget_info.xml
```

---

## 五、数据层设计

### 5.1 Room 数据库

```kotlin
@Database(
    entities = [
        NoteRecordEntity::class,
        TodoEntity::class,
        ScheduledEventEntity::class,
        EventTagEntity::class,
        CustomFolderEntity::class,
    ],
    version = 1,
    exportSchema = true
)
@TypeConverters(Converters::class)
abstract class NotieeDatabase : RoomDatabase() {
    abstract fun noteRecordDao(): NoteRecordDao
    abstract fun todoDao(): TodoDao
    abstract fun scheduledEventDao(): ScheduledEventDao
    abstract fun eventTagDao(): EventTagDao
    abstract fun customFolderDao(): CustomFolderDao
}
```

### 5.2 Entity 映射

#### NoteRecordEntity

```kotlin
@Entity(tableName = "note_records")
data class NoteRecordEntity(
    @PrimaryKey val id: String,           // UUID
    val eventId: String?,                 // FK → ScheduledEvent, nullable
    val folderId: String?,                // FK → CustomFolder, nullable
    val capturedAt: Long,                 // epoch millis
    val localImagePaths: String,          // JSON array: ["CapturedImages/<uuid>.jpg"]
    val title: String,                    // default "待处理记录"
    val ocrText: String,                  // default ""
    val summary: String,                  // default ""
    val detailedContent: String,          // default ""
    val processingState: String,          // pending|processing|completed|failed
    val isFavorite: Boolean,
    val isDeleted: Boolean,
    val editedAt: Long?,                  // nullable
    val modelsUsed: String?,              // JSON array or null
    val tokenUsage: Int,                  // default 0
    val deviceName: String?,              // Build.MODEL
)
```

#### TodoEntity

```kotlin
@Entity(
    tableName = "todos",
    foreignKeys = [ForeignKey(
        entity = NoteRecordEntity::class,
        parentColumns = ["id"],
        childColumns = ["recordId"],
        onDelete = ForeignKey.CASCADE
    )],
    indices = [Index("recordId")]
)
data class TodoEntity(
    @PrimaryKey val id: String,     // UUID
    val recordId: String?,          // FK → NoteRecord
    val content: String,
    val isCompleted: Boolean,
    val createdAt: Long,
    val dueDate: Long?,             // nullable
    val hasReminder: Boolean,
)
```

#### ScheduledEventEntity

```kotlin
@Entity(tableName = "scheduled_events")
data class ScheduledEventEntity(
    @PrimaryKey val id: String,
    val title: String,
    val startDate: Long,
    val endDate: Long,
    val kind: String,               // course|meeting|uncategorized
    val tagId: String?,             // FK → EventTag
    val updatedAt: Long,
    val source: String,             // 序列化为 JSON / 包含 type + identifier
    val notes: String?,
    val isAllDay: Boolean,
)
```

#### 其他 Entity

- **EventTagEntity**: id, name, colorHex, isSystem
- **CustomFolderEntity**: id, name, createdAt

### 5.3 加密存储 (对标 Keychain)

```kotlin
// API Keys 使用 EncryptedSharedPreferences + Android Keystore
@Singleton
class SecureKeyStore @Inject constructor(
    @ApplicationContext context: Context
) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val prefs = EncryptedSharedPreferences.create(
        context,
        "notiee_secure_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    fun saveApiKey(key: String, prefix: String)  // "vision" / "text"
    fun getApiKey(prefix: String): String?
    fun deleteApiKey(prefix: String)
}
```

### 5.4 用户偏好存储 (对标 UserDefaults)

使用 Jetpack DataStore Preferences：

```kotlin
class SettingsDataStore @Inject constructor(
    @ApplicationContext context: Context
) {
    private val dataStore = context.dataStore

    // 对标 iOS 的 UserDefaultsAppSettingsStore
    val defaultTab: Flow<AppTab>
    val theme: Flow<String>            // light|dark|system
    val fontSize: Flow<String>         // small|medium|large|extraLarge
    val language: Flow<String>         // system|zh-Hans|zh-Hant|en
    val aiEnabled: Flow<Boolean>
    val autoProcessAfterCapture: Flow<Boolean>
    val notificationEnabled: Flow<Boolean>
    val notificationAdvanceTime: Flow<Int>
    val showWeekNumbers: Flow<Boolean>
    val semesterStartDate: Flow<Long?>
    val selectedCalendarIds: Flow<Set<String>>
    // ... 等所有设置项
}
```

### 5.5 本地图片存储 (对标 LocalImageStore)

```kotlin
@Singleton
class LocalImageStore @Inject constructor(
    @ApplicationContext context: Context
) {
    private val imageDir = File(context.filesDir, "CapturedImages")

    init { imageDir.mkdirs() }

    /**
     * 保存图片，返回相对路径 "CapturedImages/<uuid>.jpg"
     */
    suspend fun saveImage(bitmap: Bitmap): String {
        val filename = "${UUID.randomUUID()}.jpg"
        val file = File(imageDir, filename)
        withContext(Dispatchers.IO) {
            file.outputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, out)
            }
        }
        return "CapturedImages/$filename"
    }

    /**
     * 从相对路径加载 Bitmap
     */
    suspend fun loadImage(relativePath: String): Bitmap? {
        val file = File(context.filesDir, relativePath)
        return withContext(Dispatchers.IO) {
            if (file.exists()) BitmapFactory.decodeFile(file.absolutePath) else null
        }
    }
}
```

---

## 六、核心服务实现

### 6.1 AI 流水线 (对标 AIProcessingService)

与 iOS 端保持完全一致的流水线：

```
1. 加载 text config + vision config
2. Stage 1 (Vision): 图片 resize(max 1024px) → compress(JPEG 0.6) → Base64
3. Stage 2 (Vision): 调用视觉模型 → 返回 OCR 文本
4. Stage 3 (Text): OCR 文本 + JSON prompt → 调用文本模型
5. 返回 AIProcessingResult(title, ocrText, summary, detailedContent, todos, modelsUsed, tokenUsage)
```

**AI API 客户端**使用 OkHttp，支持两种协议：

```kotlin
sealed interface AIClient {
    suspend fun callVision(
        endpoint: String,
        model: String,
        apiKey: String,
        base64Images: List<String>,
        prompt: String
    ): AiResponse

    suspend fun callText(
        endpoint: String,
        model: String,
        apiKey: String,
        prompt: String
    ): AiResponse
}

data class AiResponse(val content: String, val tokenUsage: Int)

// 实现
class OpenAIClient @Inject constructor(
    private val okHttpClient: OkHttpClient,
    private val moshi: Moshi
) : AIClient { ... }

class AnthropicClient @Inject constructor(
    private val okHttpClient: OkHttpClient,
    private val moshi: Moshi
) : AIClient { ... }
```

AI prompts 与 iOS 端一致，从 `strings.xml` 加载（本地化）。

### 6.2 日历服务 (对标 CalendarService + EventKit)

Android 使用 `ContentResolver` 查询 `CalendarContract`：

```kotlin
@Singleton
class AndroidCalendarService @Inject constructor(
    @ApplicationContext private val context: Context
) {
    // 权限: android.permission.READ_CALENDAR

    suspend fun requestAccess(): Boolean { ... }

    /**
     * 获取指定时间范围内的日程事件
     * 默认范围：-1 个月 到 +6 个月（与 iOS 端一致）
     */
    suspend fun fetchEvents(currentDate: LocalDate): List<ScheduledEvent> {
        // 查询 CalendarContract.Instances
        // 过滤已选中日历
        // 事件类型推断（标题含 "课"/"Class" → course, "会"/"Meeting" → meeting）
    }

    /**
     * 获取特殊日事件（节假日、生日、节气）
     * 注：Android 无内置节气数据，需集成第三方日历或手动维护阳光府日历数据
     * 暂定方案：仅支支持生日的读取，节假日由用户自行通过 .ics 导入
     */
    suspend fun specialDayEvents(date: LocalDate): List<SpecialDayEvent> { ... }

    fun selectedCalendarIds(): Set<String> { ... }
    fun saveSelectedCalendarIds(ids: Set<String>) { ... }
}
```

**关键差异**：Android 无内置中国节假日/节气。方案：
- 生日：通过 `ContactsContract` 读取
- 节假日：建议集成 [chinese-calendar](https://github.com/6tail/lunar-java) 库，或由用户通过 .ics 导入
- 节气：同样依赖 lunar-java 库

### 6.3 相机服务 (对标 CameraManager + AVFoundation)

使用 CameraX：

```kotlin
@Singleton
class CameraManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val cameraProviderFuture = ProcessCameraProvider.getInstance(context)

    enum class Status { UNCONFIGURED, UNAUTHORIZED, READY, FAILED }

    var status: Status by mutableStateOf(Status.UNCONFIGURED)
        private set

    var capturedBitmap: Bitmap? by mutableStateOf(null)
        private set

    private var imageCapture: ImageCapture? = null
    private var camera: Camera? = null

    fun bindToLifecycle(lifecycleOwner: LifecycleOwner) { ... }

    suspend fun capturePhoto(): Bitmap {
        // 使用 ImageCapture.takePicture()
        // 模拟器上返回占位图
    }

    fun setZoom(linearZoom: Float) { ... }  // CameraX linear zoom 0.0-1.0
    fun setFlashMode(mode: Int) { ... }     // FLASH_MODE_AUTO/ON/OFF
    fun startCamera() { ... }
    fun stopCamera() { ... }
}
```

**与 iOS 差异**：
- iOS 18 `LockedCameraCapture` 扩展 → Android 无等价物。使用 `KeyguardManager` + 锁屏快捷方式（厂商支持有限）
- iOS `AVCaptureEventInteraction` (Camera Control 按钮) → 无等价物

### 6.4 通知服务 (对标 NotificationManager + LiveActivityManager)

```kotlin
@Singleton
class NotieeNotificationManager @Inject constructor(
    @ApplicationContext private val context: Context
) {
    init {
        // 创建通知渠道
        createChannels()
    }

    suspend fun requestPermission(): Boolean { ... }

    /**
     * 为即将到来的日程排布提醒
     * 对标 iOS 的 scheduleNotifications(for:advanceTimeMinutes:)
     */
    fun scheduleEventReminders(events: List<ScheduledEvent>, advanceMinutes: Int) {
        // 使用 WorkManager 的 OneTimeWorkRequest
        // 延迟到 startDate - advanceMinutes 触发
    }
}
```

**Live Activities 替代方案**：

iOS Dynamic Island 无直接 Android 等价物。降级方案：
1. **前台服务通知** — 当前日程进行中时显示持续通知（含进度条，显示剩余时间）
2. **Glance 小组件** — 桌面显示当前进行中的日程

### 6.5 桌面小组件 (对标 WidgetKit)

使用 Jetpack Glance：

```kotlin
class NotieeWidget : GlanceAppWidget() {

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            // 显示今日日程列表
            // 点击跳转到 app
        }
    }
}

class NotieeWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = NotieeWidget()
}
```

### 6.6 引导流程 (对标 PrivacyAgreement + Welcome + WhatsNew)

```kotlin
// MainActivity.kt
@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            NotieeApp()
        }
    }
}

@Composable
fun NotieeApp() {
    val settingsDataStore = hiltViewModel<SettingsViewModel>()

    // 1. 隐私协议 → 2. 欢迎引导 → 3. 新版本提示 → 4. 主页
    var step by remember { mutableStateOf(AppStartStep.PRIVACY) }

    when (step) {
        AppStartStep.PRIVACY -> PrivacyAgreementScreen(
            onAgree = { step = nextStep() }
        )
        AppStartStep.WELCOME -> WelcomeScreen(
            onComplete = {
                // 请求权限: 相机/麦克风/相册/日历/通知
                PermissionManager.requestAll(context)
                step = nextStep()
            }
        )
        AppStartStep.WHATS_NEW -> WhatsNewScreen(
            onDismiss = { step = AppStartStep.MAIN }
        )
        AppStartStep.MAIN -> RootScreen()
    }
}
```

---

## 七、UI 设计规范

### 7.1 Material 3 主题

```kotlin
// Theme.kt — 对标 iOS 的 system/light/dark 三种主题模式
@Composable
fun NotieeTheme(
    themeMode: String = "system",  // light | dark | system
    fontSize: String = "medium",   // small | medium | large | extraLarge
    content: @Composable () -> Unit
) {
    val darkTheme = when (themeMode) {
        "dark" -> true
        "light" -> false
        else -> isSystemInDarkTheme()
    }

    val typography = when (fontSize) {
        "small" -> SmallTypography
        "large" -> LargeTypography
        "extraLarge" -> ExtraLargeTypography
        else -> MediumTypography
    }

    MaterialTheme(
        colorScheme = if (darkTheme) darkColorScheme(...) else lightColorScheme(...),
        typography = typography,
        content = content
    )
}
```

### 7.2 导航结构

```kotlin
@Composable
fun RootScreen() {
    val navController = rememberNavController()

    Scaffold(
        bottomBar = {
            NavigationBar {
                AppTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = currentTab == tab,
                        onClick = { navController.navigate(tab.route) { ... } },
                        icon = { Icon(tab.icon, contentDescription = tab.title) },
                        label = { Text(tab.title) }
                    )
                }
            }
        }
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = AppTab.TODAY.route,
            modifier = Modifier.padding(padding)
        ) {
            composable(AppTab.TODAY.route) { TodayScreen(navController) }
            composable(AppTab.CAPTURE.route) { CaptureScreen(navController) }
            composable(AppTab.RECORDS.route) { RecordsScreen(navController) }
            composable(AppTab.SETTINGS.route) { SettingsScreen(navController) }
            composable("record/{recordId}") { ... }
            composable("event/{eventId}") { ... }
            // ...
        }
    }
}
```

### 7.3 Tab 映射

| Tab | iOS SF Symbol | Android Icon | 中文 |
|-----|---------------|-------------|------|
| Today | `calendar` | `Icons.Rounded.CalendarMonth` | 今日 |
| Capture | `camera.viewfinder` | `Icons.Rounded.CameraAlt` | 拍记 |
| Records | `book.closed` | `Icons.Rounded.MenuBook` | 记录 |
| Me | `person.crop.circle` | `Icons.Rounded.Person` | 我的 |

---

## 八、分阶段实施计划

### Phase 1: 项目骨架 (预计 3-4 人天)

| 任务 | 产出 | 优先级 |
|------|------|--------|
| 创建 Android 项目 (Gradle KTS + Version Catalog) | 基础构建配置 | P0 |
| 配置 Hilt DI | AppModule / DatabaseModule / ServiceModule | P0 |
| 配置 Room 数据库 + 所有 Entity | NotieeDatabase + 5 个 DAO | P0 |
| 实现 SettingsDataStore | 所有用户偏好 Storage | P0 |
| 实现 SecureKeyStore | API Key 加密存储 | P0 |
| 配置主题 (Material 3) | Theme.kt + dark/light | P0 |
| 实现 RootScreen + 4-tab 导航 | 空壳页面可导航 | P0 |
| 实现引导流程 (隐私/欢迎/WhatsNew) | 3 个引导页 | P0 |
| 创建 strings.xml (三语) | 对标 iOS 279 条 | P0 |

**里程碑 M1**: App 可运行，4 个 Tab 可切换，引导流程走通，主题切换正常。

### Phase 2: 核心数据层 (预计 4-5 人天)

| 任务 | 产出 | 优先级 |
|------|------|--------|
| 实现 NoteRecordRepositoryImpl | 笔记 CRUD + Flow | P0 |
| 实现 TodoRepositoryImpl | 待办 CRUD + Flow | P0 |
| 实现 ScheduledEventRepositoryImpl | 日程 CRUD + Flow | P0 |
| 实现 EventTagRepositoryImpl | 标签 CRUD + Flow | P0 |
| 实现 CustomFolderRepositoryImpl | 文件夹 CRUD + Flow | P0 |
| 实现 LocalImageStore | 图片保存/加载 | P0 |
| 实现 MainStore (对标 NotieeStore) | 全局状态持有者 | P0 |
| 编写 Repository 层单元测试 | Mock DAO 测试 | P1 |

**里程碑 M2**: 完整的数据读写链路打通，MainStore 作为唯一数据源。

### Phase 3: 相机 + 记录创建 (预计 3-4 人天)

| 任务 | 产出 | 优先级 |
|------|------|--------|
| 实现 CameraManager (CameraX) | 预览/拍照/闪光灯/变焦 | P0 |
| 实现 CaptureScreen | 全屏相机 UI | P0 |
| 实现 CaptureViewModel | 拍照 → 创建记录 → 关联日程 | P0 |
| 实现连拍模式 (batch, max 9) | 多张图片生成一条记录 | P1 |
| 实现相册导入 | PhotoPicker 集成 | P1 |
| 实现 RecordDetailScreen (基础版) | 图片轮播 + 基本信息展示 | P0 |
| 实现 FullScreenImageView | 双指缩放 | P1 |

**里程碑 M3**: 可拍照、创建记录、查看记录详情。

### Phase 4: 日历集成 (预计 3-4 人天)

| 任务 | 产出 | 优先级 |
|------|------|--------|
| 实现 AndroidCalendarService | 读取系统日历 | P0 |
| 实现 ScheduleMatcher | 当前日程匹配 | P0 |
| 实现 TodayScreen | 时间线 UI | P0 |
| 实现 TodayViewModel | 日程/待办/记录聚合 | P0 |
| 实现 CreateItemSheet | 手动创建日程/待办 | P0 |
| 实现 EventDetailView | 日程详情 + 关联记录 | P1 |
| 实现 SpecialDayEvent 检测 | 生日/节假日检测 | P2 |
| 实现通知提醒 | WorkManager 排程 | P1 |

**里程碑 M4**: 日历集成完成，今日页面可用。

### Phase 5: AI 流水线 (预计 3-4 人天)

| 任务 | 产出 | 优先级 |
|------|------|--------|
| 实现 AIClient (OpenAI + Anthropic) | OkHttp 双协议支持 | P0 |
| 实现 RealAIProcessor | 视觉 + 文本两阶段流水线 | P0 |
| 实现 MockAIProcessor | 模拟 AI 响应（测试用） | P0 |
| 实现 AIConfigurationScreen | AI 服务商配置 UI | P0 |
| 实现 CustomModelsScreen | 自定义模型管理 | P1 |
| 实现 AI 流水线接入 MainStore | 拍照后自动/手动触发 AI | P0 |
| 实现 AI 结果更新 UI | 摘要/待办/详细内容展示 | P0 |
| 实现连接测试 | API 连通性验证 | P1 |

**里程碑 M5**: AI 流水线完整可用。

### Phase 6: 记录管理完整版 (预计 3-4 人天)

| 任务 | 产出 | 优先级 |
|------|------|--------|
| 实现 RecordsScreen | 文件夹/事件/搜索列表 | P0 |
| 实现 RecordDetailScreen (完整版) | 所有可折叠区域 + 编辑 | P0 |
| 实现 RecordEditSheet | 编辑所有字段 | P0 |
| 实现 SwipeableTodoRow | 滑动完成/删除 | P1 |
| 实现 MarkdownContent 组件 | Markdown 渲染 | P1 |
| 实现搜索 + 高亮 | HighlightedText | P0 |
| 实现文件夹管理 | 创建/重命名/删除 | P0 |
| 实现收藏/回收站功能 | 软删除 + 恢复 | P0 |

**里程碑 M6**: 记录管理模块完整。

### Phase 7: TMN 导入导出 + 设置页 (预计 3-4 人天)

| 任务 | 产出 | 优先级 |
|------|------|--------|
| 实现 TmnExporter | 单条/批量导出 | P0 |
| 实现 TmnImporter | 单条/批量导入 | P0 |
| 实现 BackupRestoreScreen | 备份恢复 UI | P0 |
| 实现 SettingsScreen (完整版) | 所有设置项 | P0 |
| 实现 ImportScheduleScreen | .ics 导入 + AI 解析 | P1 |
| 实现 ReviewScreen | Token 用量统计 | P2 |
| 实现 LabFeaturesScreen | 实验室功能 | P2 |
| 实现 AboutNotieeScreen | 关于页面 | P2 |
| 实现桌面小组件 (Glance) | 日程卡片小组件 | P2 |

**里程碑 M7**: 所有功能模块完成，可进行端到端测试。

### Phase 8: 打磨 + 测试 + 发布 (预计 3-4 人天)

| 任务 | 产出 | 优先级 |
|------|------|--------|
| 全量 UI 测试 | Compose Testing | P0 |
| 全量单元测试 (对齐 iOS 28 个用例) | JUnit | P0 |
| 多语言复查 | 三语完整性 | P0 |
| 性能优化 (列表加载/图片缓存) | Profile 优化 | P1 |
| 无障碍适配 | TalkBack 支持 | P2 |
| Play Store 上架准备 | 截图/描述/隐私政策 | P0 |

**里程碑 M8**: 可发布版本。

### 时间估算总汇

| Phase | 工作内容 | 人天 | 累计 |
|-------|---------|------|------|
| P1 | 项目骨架 | 3-4 | 4 |
| P2 | 核心数据层 | 4-5 | 9 |
| P3 | 相机 + 记录创建 | 3-4 | 13 |
| P4 | 日历集成 | 3-4 | 17 |
| P5 | AI 流水线 | 3-4 | 21 |
| P6 | 记录管理完整版 | 3-4 | 25 |
| P7 | TMN + 设置页 | 3-4 | 29 |
| P8 | 打磨 + 测试 + 发布 | 3-4 | 33 |

**总计：约 33 人天**（约 6.5 人周），适合 1 位 Android 工程师全职投入 1.5-2 个月。

---

## 九、风险与应对

| 风险 | 影响 | 概率 | 应对策略 |
|------|------|------|---------|
| **Dynamic Island 无等价物** | 日程进行中状态展示降级 | 确定 | 使用前台服务 + 持续通知替代；Glance 小组件作为补充 |
| **iOS 18 Locked Camera 无等价物** | 锁屏拍照快捷方式缺失 | 确定 | 部分 Android 厂商支持锁屏快捷方式（Samsung/OnePlus），但不通用。暂不实现，未来可评估厂商 SDK |
| **中国节假日/节气数据缺失** | SpecialDayEvent 功能降级 | 确定 | 集成 `lunar-java` 库，或提示用户手动导入 `.ics` |
| **iCloud Sync 无等价物** | 云同步功能降级 | 低 | iCloud 本身是实验室功能。可评估 Firebase Firestore / 自建后端 |
| **.tmn 格式兼容性** | 双端互导失败 | 中 | 尽早实现 TmnValidator + 双端交叉测试 |
| **CameraX 稳定性** | 不同厂商相机行为差异 | 中 | 充分的设备兼容性测试（Pixel/Samsung/Xiaomi/Huawei） |
| **AI 流水线行为差异** | 双端 AI 结果不一致 | 低 | 使用相同 prompts 和相同 API，理论上结果一致。加入 Mock 测试保证流水线逻辑一致 |
| **Markdown 渲染质量** | UI 一致性差异 | 低 | iOS 使用 `swift-markdown-ui`，Android 使用 `compose-markdown` 或其他库 |

---

## 十、测试策略

### 10.1 单元测试（对标 iOS 28 个测试）

| 测试文件 | 测试目标 | 对标 iOS |
|---------|---------|---------|
| `MainStoreTest` | capturePhoto 存储 + 持久化；records 搜索 | NotieeStoreTests |
| `TodayViewModelTest` | sample 数据正确性；pendingTodos 过滤；todayRecords 过滤 | TodayViewModelTests |
| `ScheduleMatcherTest` | 无匹配返回 null；匹配当前事件；优先选最近更新 | ScheduleMatcherTests |
| `CaptureViewModelTest` | 无事件时回退为 "未分类"；无当前事件标题；多张连拍顺序 | CaptureViewModelTests |
| `SettingsViewModelTest` | defaultTab 持久化往返；API Key 不在普通存储中；连接测试需完整配置 | SettingsViewModelTests |
| `RecordDetailViewModelTest` | 正确解析 event/title/summary/ocr/todos；无事件时回退未分类 | RecordDetailViewModelTests |
| `MockAIProcessorTest` | 任意/nil 事件返回结果；fail 路径抛异常；auto-process 状态转换正确；结果填充完整；todos 正确创建；不开启 auto-process 保持 pending；手动触发正常；updateRecord 更新；addTodo 追加 | MockAIProcessingServiceTests |
| `ProjectConfigTest` | 启动画面声明；logo 资源存在 | ProjectConfigurationTests |

### 10.2 UI 测试 (Compose Testing)

- 4 个 Tab 导航切换正常
- 引导流程完整通过
- Today 页面三种事件区域折叠/展开
- 相机拍照 → 保存 → 列表显示
- 记录详情折叠区域展开/收起
- 设置页各项配置持久化

### 10.3 集成测试

- TMN 导出 → iOS 端导入 → 数据一致性
- TMN 导入 ← iOS 端导出 → 数据一致性
- AI 流水线端到端 (Mock + Real)
- 日历同步正确性

---

## 十一、配置清单

### 11.1 AndroidManifest.xml 权限声明

```xml
<!-- 对标 iOS Info.plist -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" /> <!-- API 33+ -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.READ_CALENDAR" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" /> <!-- 重启后恢复通知 -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" /> <!-- 日程提醒 -->
<uses-permission android:name="android.permission.USE_EXACT_ALARM" /> <!-- 精确闹钟 -->

<!-- 桌面小组件 -->
<receiver android:name=".service.widget.NotieeWidgetReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data android:name="android.appwidget.provider"
        android:resource="@xml/notiee_widget_info" />
</receiver>
```

### 11.2 Version Catalog (libs.versions.toml)

```toml
[versions]
kotlin = "2.1.0"
compose-bom = "2025.05.00"
room = "2.7.1"
hilt = "2.53.1"
coil = "2.7.0"
okhttp = "4.12.0"
moshi = "1.15.2"
camerax = "1.4.1"
work = "2.10.0"
datastore = "1.1.2"
security-crypto = "1.1.0-alpha06"
lifecycle = "2.9.0"
navigation = "2.9.0"
glance = "1.1.1"
accompanist = "0.36.0"
aboutlibraries = "11.2.0"
lottie = "6.6.2"

[libraries]
compose-bom = { group = "androidx.compose", name = "compose-bom", version.ref = "compose-bom" }
compose-material3 = { group = "androidx.compose.material3", name = "material3" }
compose-ui = { group = "androidx.compose.ui", name = "ui" }
compose-ui-tooling = { group = "androidx.compose.ui", name = "ui-tooling" }
compose-ui-tooling-preview = { group = "androidx.compose.ui", name = "ui-tooling-preview" }

room-runtime = { group = "androidx.room", name = "room-runtime", version.ref = "room" }
room-ktx = { group = "androidx.room", name = "room-ktx", version.ref = "room" }
room-compiler = { group = "androidx.room", name = "room-compiler", version.ref = "room" }

hilt-android = { group = "com.google.dagger", name = "hilt-android", version.ref = "hilt" }
hilt-compiler = { group = "com.google.dagger", name = "hilt-android-compiler", version.ref = "hilt" }
hilt-navigation-compose = { group = "androidx.hilt", name = "hilt-navigation-compose", version = "1.2.0" }
hilt-work = { group = "androidx.hilt", name = "hilt-work", version = "1.2.0" }

coil-compose = { group = "io.coil-kt", name = "coil-compose", version.ref = "coil" }
okhttp = { group = "com.squareup.okhttp3", name = "okhttp", version.ref = "okhttp" }
moshi = { group = "com.squareup.moshi", name = "moshi-kotlin", version.ref = "moshi" }
moshi-codegen = { group = "com.squareup.moshi", name = "moshi-kotlin-codegen", version.ref = "moshi" }

camerax-camera2 = { group = "androidx.camera", name = "camera-camera2", version.ref = "camerax" }
camerax-lifecycle = { group = "androidx.camera", name = "camera-lifecycle", version.ref = "camerax" }
camerax-view = { group = "androidx.camera", name = "camera-view", version.ref = "camerax" }

work-runtime-ktx = { group = "androidx.work", name = "work-runtime-ktx", version.ref = "work" }
work-testing = { group = "androidx.work", name = "work-testing", version.ref = "work" }

datastore-preferences = { group = "androidx.datastore", name = "datastore-preferences", version.ref = "datastore" }
security-crypto = { group = "androidx.security", name = "security-crypto", version.ref = "security-crypto" }

lifecycle-viewmodel-compose = { group = "androidx.lifecycle", name = "lifecycle-viewmodel-compose", version.ref = "lifecycle" }
lifecycle-runtime-compose = { group = "androidx.lifecycle", name = "lifecycle-runtime-compose", version.ref = "lifecycle" }

navigation-compose = { group = "androidx.navigation", name = "navigation-compose", version.ref = "navigation" }
glance-appwidget = { group = "androidx.glance", name = "glance-appwidget", version.ref = "glance" }
accompanist-permissions = { group = "com.google.accompanist", name = "accompanist-permissions", version.ref = "accompanist" }
aboutlibraries-compose = { group = "com.mikepenz", name = "aboutlibraries-compose-m3", version.ref = "aboutlibraries" }
lottie-compose = { group = "com.airbnb.android", name = "lottie-compose", version.ref = "lottie" }

# 可选：中国日历
lunar-java = { group = "cn.6tail", name = "lunar", version = "1.5.8" }

[plugins]
kotlin-android = { id = "org.jetbrains.kotlin.android", version.ref = "kotlin" }
kotlin-compose = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
kotlin-kapt = { id = "org.jetbrains.kotlin.kapt", version.ref = "kotlin" }
hilt = { id = "com.google.dagger.hilt.android", version.ref = "hilt" }
room = { id = "androidx.room", version.ref = "room" }
ksp = { id = "com.google.devtools.ksp", version = "2.1.0-1.0.29" }
```

### 11.3 Gradle 配置要点

```kotlin
// app/build.gradle.kts
android {
    namespace = "com.notiee.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.notiee.app"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.1"
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "2.1.0"
    }
}

kapt {
    correctErrorTypes = true
}
```

---

## 十二、与 iOS 端的关键差异总结

| 功能 | iOS | Android | 差异说明 |
|------|-----|---------|---------|
| **动态岛 / Live Activities** | ActivityKit + WidgetKit | 前台服务通知 + Glance 小组件 | Android 无等价物，降级方案 |
| **锁屏相机** | iOS 18 LockedCameraCapture 扩展 | 无等价物 | 跳过此功能 |
| **Camera Control 按钮** | AVCaptureEventInteraction (iPhone 16+) | 无硬件按钮 | 跳过此功能 |
| **中国节气** | 系统日历内置 | 需 `lunar-java` 库 | 引入第三方库 |
| **系统分享菜单** | UIActivityViewController | `Intent.ACTION_SEND` + ShareSheet | Android 更灵活，支持更多 target |
| **iCloud 同步** | CloudKit | 暂无 | iCloud 在 iOS 已是实验室功能，不影响 MVP |
| **应用内评分** | SKStoreReviewController | Google Play In-App Review API | 接口不同，功能等价 |
| **后台刷新** | BGAppRefreshTask | WorkManager PeriodicWork | WorkManager 更可靠 |
| **照片选择器** | PHPickerViewController | `ActivityResultContracts.PickVisualMedia` | 功能等价 |
| **文件选择器** | UIDocumentPickerViewController | `ActivityResultContracts.OpenDocument` | 功能等价 |

---

## 十三、文件管理

### 13.1 `.tmn` 格式兼容性保证

`.tmn` 格式定义为 ZIP 容器，包含 `manifest.json` + `content.json` + `attachments/`，是平台无关的标准格式，Android 端需保证：

1. **写入**：`TmnExporter` 生成与 iOS 端完全一致的 JSON 结构
2. **读取**：`TmnImporter` 能解析 iOS 端生成的任何合法 `.tmn` 文件
3. **校验**：`TmnValidator` 在导入前检查 `format: "tmn/zip/v1"` 和 `content.type: "record"`
4. **UUID 兼容**：双端使用相同的 UUID 格式（8-4-4-4-12）

### 13.2 Intent Filter 注册

```xml
<!-- 对标 iOS 的 UTI 声明 -->
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:scheme="file" />
    <data android:scheme="content" />
    <data android:mimeType="*/*" />
    <data android:pathPattern=".*\\.tmn" />
</intent-filter>
```

---

## 十四、附录

### A. iOS SPM 依赖 → Android 等价物速查

| iOS (SPM) | 版本 | Android | 版本 |
|-----------|------|---------|------|
| ZIPFoundation | 0.9.20 | `java.util.zip` (JDK) | — |
| swift-markdown-ui | 2.4.1 | 自建 MarkdownContent 组件 或 `com.github.jeziellago:compose-markdown` | 0.5.0 |
| NetworkImage | 6.0.1 | Coil | 2.7+ |
| OnboardingKit | main | 自建 Compose 引导页 | — |
| PageView | 0.2.0 | `HorizontalPager` (Compose Foundation) | — |
| WhatsNewKit | main | 自建 WhatsNewScreen | — |
| swift-cmark | 0.8.0 | CommonMark 库 (如需) | — |

### B. iOS 系统 API → Android 等价物速查

| iOS API | Android API |
|---------|-------------|
| `@MainActor` | `viewModelScope` / `withContext(Dispatchers.Main)` |
| `ObservableObject` + `@Published` | `StateFlow` + `collectAsState()` |
| `@AppStorage` | `DataStore Preferences` |
| `Keychain` (`SecItem*`) | `EncryptedSharedPreferences` + Android Keystore |
| `EventKit` (`EKEventStore`) | `ContentResolver` + `CalendarContract` |
| `AVCaptureSession` | `ProcessCameraProvider` (CameraX) |
| `PHPhotoLibrary` | `MediaStore` |
| `SFSpeechRecognizer` | `SpeechRecognizer` (android.speech) |
| `UNUserNotificationCenter` | `NotificationManagerCompat` |
| `ActivityKit` | Foreground Service + Notification |
| `WidgetKit` | Glance |
| `Combine` (`@Published`, `sink`) | Kotlin Flow (`collect`, `combine`) |
| `Codable` | Moshi / kotlinx.serialization |
| `FileManager` | `java.io.File` / `Context.filesDir` |
| `UserDefaults` | `DataStore` / `SharedPreferences` |
| `UIPasteboard` | `ClipboardManager` |
| `UIDevice.current.modelName` | `Build.MODEL` |
