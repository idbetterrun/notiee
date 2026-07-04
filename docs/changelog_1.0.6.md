# Notiee 1.0.6 更新日志

> 发布日期：2026 年 7 月 2 日

---

## 笔记加密 & 隐私锁

1.0.6 最大的更新——为你的笔记加上端到端的安全保护：

### 单条笔记加密

- **一键加密**：记录详情页工具栏新增加密按钮（锁形图标），点击后输入密码即可为当前笔记加密。加密状态通过 `NoteRecord.isEncrypted` 标记。
- **AES-GCM 加密**：`CryptoService` 使用 AES-256-GCM 算法加密笔记内容，密钥由密码通过 PBKDF2 派生，DEK（Data Encryption Key）存于 iOS Keychain。
- **加密覆盖范围**：标题、OCR 文字、AI 摘要、详细内容、关键点、定义、待办事项全部加密，加密后存储为 base64 密文。
- **锁定占位**：记录列表卡片和缩略图中，加密笔记显示锁定图标和"已加密"占位文字，摘要隐藏，确保密文不泄露。

### 隐私锁

- **全局应用锁**：`AppLockManager` 支持 Face ID / Touch ID 生物识别 + 数字密码两种解锁方式。进入后台超时（默认 1 分钟）后回到前台需重新解锁。
- **AppLockView 覆盖层**：应用进入后台被锁定后，全屏覆盖密码/面容界面，验证通过后才显示真实内容。基于 `scenePhase` 自动触发。
- **安全设置页面**：新增专用设置页（入口在「我」→「安全与隐私」），可开关隐私锁、设定密码、开启生物识别、调整后台锁定时间。

### 加密隔离策略

- **导出隔离**：`.tmn` 导出自动排除加密记录。
- **同步隔离**：iCloud 同步跳过加密记录。
- **搜索隔离**：全文搜索和语义检索不命中加密笔记。
- **索引隔离**：语义向量索引构建时跳过加密记录。
- **Agent 隔离**：Spark Agent 的搜索、读取、删除工具均跳过加密笔记。

---

## Sign in with Apple

- **Apple 登录**：`AccountStore` 接入 Apple 原生 `ASAuthorizationAppleIDProvider`，支持通过 Face ID / Touch ID 一键登录。
- **隐私保护**：使用 Apple 的私有邮箱转发（Hide My Email），首次登录时会要求确认是否共享真实邮箱；每次登录需面容/触控 ID 二次认证。
- **UI 更新**：
  - 登录页新增 Apple 风格登录按钮（黑色/白色自适应），图标来自 SF Symbols。
  - 用户头像区域支持注销（长按），注销后立即回到未登录状态。
  - 设置页登录入口调整为 `SignInWithAppleButton`。
- **法律合规**：隐私协议和用户条款中补充 Apple 登录相关条款，明确数据收集仅为 iCloud 同步所需的最小范围。

---

## 多语言输出

实验室新增「拍记输出语言」配置，控制 AI 处理结果的语言：

- **自动跟随**：默认「自动（跟随内容）」，AI 按图片/文字中检测到的语言生成同种语言的摘要和待办。
- **固定语言**：支持 8 种语言固定输出——简体中文、繁體中文、English、한국어、日本語、Français、Deutsch、Español。
- **实现原理**：`AIPromptProvider` 在构造 AI prompt 时追加语言指令（如 `Respond in English`），`RealAIProcessingService` 和 Spark Agent 均已适配。

---

## 自定义模型改进

- **模型选择器修复**：用户在设置中添加的自定义模型现在能正确出现在文字模型和视觉模型选择器中（此前仅显示系统预设模型）。
- **实现**：`SettingsViewModel` 新增 `customModelsByKind()` 辅助方法，按 `ModelKind.text` / `.vision` 过滤，`AIConfigurationView` 和 `RecordDetailViewModel` 均已适配。

---

## iCloud 同步修复

- **容器配置**：补充 `Notiee.entitlements` 中的 iCloud 容器标识符（`iCloud.com.idbetterrun.notiee`）和 `CloudDocuments` 服务声明，此前数组为空导致 `forUbiquityContainerIdentifier(nil)` 返回 `nil`。
- **下载竞态修复**：原 `downloadCloudFiles` 调用 `startDownloadingUbiquitousItem` 后立即读取文件，此时文件尚未下载完成。现改为轮询等待最多 30 秒，检查 `ubiquitousItemDownloadingStatusKey != .notDownloaded` 后继续。
- **文件协调**：所有 iCloud 容器内的文件操作（创建目录、拷贝文件、读取目录）均通过 `NSFileCoordinator` 包裹，防止多设备并发操作导致冲突。
- **Notiee+ 容器**：Notiee 与 Notiee+ 共用同一 iCloud 容器，确保用户在两版 App 之间的数据互通。

---

## Notiee+ 修复

- **Widget Bundle ID**：修正 Notiee+ Widget Extension 的嵌入配置，Widget 不再因 bundle-id 不匹配而无法加载。
- **品牌统一**：Notiee+ 的开屏启动画面、隐私协议页 Logo 等品牌元素已对齐主应用风格。
- **开屏过渡**：启动封面引入声明式淡入动画（`withAnimation(.easeIn(duration: 0.25))`），消除突兀的闪现，过渡更顺滑。

---

## 法务文档扩展

- **新增语言**：补充英文（en）、港澳繁體（zh-Hant-HK）、台灣繁體（zh-Hant-TW）版本的用户协议和隐私政策。
- **路由机制**：`LegalHTMLView` 根据 App 当前语言和设备地区自动选择最匹配的法律文档。
- **开源鸣谢更新**：`OpenSourceAcknowledgmentsView` 与当前 bundled dependencies 同步，新增 ZIPFoundation、swift-cmark、OnboardingKit、WhatsNewKit、MarkdownUI、PageView 等依赖项致谢。

---

## P0 缺陷修复

一轮集中的关键缺陷修复（共涉及 9 个模块）：

| 模块 | 修复内容 |
|------|----------|
| `JSONNoteRecordStore` | 防御性解码：解析失败时隔离损坏文件而非崩溃，由 `PersistenceRecovery` 接管 |
| `PersistenceRecovery` | 新增文件损坏隔离机制，损坏 JSON 自动移至 `quarantine/` 目录并创建空备份 |
| `LocalImageStore` | 删除记录时同步删除关联图片文件，防止磁盘垃圾累积 |
| `EmbeddingIndex` | 语义索引清理时移除孤立向量条目，删除记录时更新索引标签 |
| `RecordManager` | 删除记录回调链中注入索引清理和图片清理逻辑 |
| `KeychainSecretStore` | 修复 Keychain query 中缺失 `kSecAttrAccount` 导致的读写失败 |
| `TMNImportService` | 防御路径遍历攻击：`secureResolve()` 限制解压文件不得超出沙盒目录 |
| `AgentExecutor` | 删除类工具（Note/Schedule/Todo）在被撤销后不再执行，修复 undo 循环 |
| `NotieeStore` | 预览/示例数据隔离：`previewStore` 使用独立的临时目录，不污染用户真实数据 |

---

## 技术细节

| 项目 | 说明 |
|------|------|
| 新增文件 | `CryptoService.swift`、`SecureRecordCodec.swift`、`AppLockManager.swift`、`AppLockView.swift`、`SecuritySettingsView.swift`；法律文档 HTML × 6（en / zh-Hant-HK / zh-Hant-TW 各 2 个）；测试文件 `CryptoServiceTests.swift`、`SecureRecordCodecTests.swift`、`PersistenceRecoveryTests.swift`、`LocalImageStoreDeleteTests.swift`、`CustomModelKeychainTests.swift`、`AgentUndoDeleteToolsTests.swift`、`NoteRecordEncryptedDecodingTests.swift`、`NoteTodoDecodingTests.swift`、`RecordDeletionHookTests.swift`、`TMNPathSafetyTests.swift`、`AIPromptOutputLanguageTests.swift` 等 |
| 修改文件 | `NoteRecord.swift`（新增 `isEncrypted` 字段）、`NotieeStore.swift`（加密/解密编排）、`RecordManager.swift`（删除回调链）、`RecordDetailView.swift`（加密按钮 + 锁定视图）、`RecordCardView.swift`（加密占位）、`RecordThumbnailView.swift`（锁图标）、`TMNExportService.swift`（排除加密记录）、`ICloudSyncService.swift`（排除加密记录 + 下载竞态修复 + NSFileCoordinator）、`SemanticSearchEngine.swift`（排除加密记录）、`EmbeddingService.swift`（排除加密记录）、`Agent` 工具类（NoteSearch/NoteGetDetail/NoteUpdate 跳过加密记录）、`UserDefaultsKeys.swift`（安全相关新 key）、`UserDefaultsAppSettingsStore.swift`（安全设置持久化）、`AIPromptProvider.swift`（输出语言指令）、`Notiee.entitlements`（iCloud 容器配置）、`WhatsNewView.swift`（更新内容文案） |
| 第三方依赖 | 无变化 |
| 系统权限 | 新增 `NSFaceIDUsageDescription`（"Notiee 使用面容 ID 保护你的加密笔记和数据隐私"） |
| 向后兼容 | `isEncrypted` 字段缺失时默认 `false`，旧版本数据自动视为未加密；损坏文件隔离不会丢失原始数据（存于 quarantine 目录）；加密/隐私锁为可选功能，不开启时行为与 1.0.5 完全一致 |

---

## 已知限制

- **加密笔记**暂不支持全文搜索和语义检索（加密后内容不可索引，这属于设计决策而非缺陷）。
- **iCloud 同步**为手动触发（实验室功能菜单按钮），暂无自动后台同步，上传/下载需用户主动操作。
- **隐私锁**不支持多用户；密码重设会清空所有加密记录（因 DEK 无法解密）。
- **Sign in with Apple** 当前仅用于登录标识，暂未与 iCloud 容器权限或跨设备同步绑定（后续版本将整合）。

---

> **版本历史**
> - **v1.0.6**（2026-07-02）：笔记加密 & 隐私锁、Sign in with Apple、多语言输出、自定义模型修复、iCloud 同步修复、P0 缺陷修复、Notiee+ 品牌对齐
> - v1.0.5（2026-06-24）：纯文字记录、深度联想 / 相关笔记推荐、日程彩色标签、法务多语种本地化、待办持久化明确
> - v1.0.4（2026-06-24，未公开发布）：本地账户系统、Spark Agent 工具扩展、RAG 语义检索、全量待办管理、记录来源区分、iOS 26 Liquid Glass 适配
> - v1.0.3（2026-06-04）：Spark AI 助手、Agent 模式、多语言适配
> - v1.0.1：初始版本
