# Notiee 1.0.4 更新日志

> 发布日期：2026年6月24日

---

## 本地账户系统

新增个人资料功能，让你在 App 内拥有自己的身份标识：

- **本地登录**：设置昵称和头像，所有信息仅保存在本机，不上传任何服务器
- **个人资料编辑**：随时修改昵称、更换头像
- **MeView 两态**：已登录显示头像，未登录引导登录

## Spark Agent 工具扩展

Spark 的 Agent 模式新增多个实用工具，让它能帮你做更多事：

- **日程修改**（schedule_update）：Agent 现在可以帮你修改已有日程的时间、标题等信息
- **日期查询**（date_info）：精确查询某天是星期几、日期间隔等，不再依赖模型猜测
- **网页抓取**（web_fetch）：在 Agent 模式下提供链接，Spark 可抓取网页正文内容作为参考
  - 内置安全防护：禁止访问本地及内网地址，使用临时网络会话（不持久化 Cookie/缓存）

## Spark 隐私规则重构

重新梳理 Spark 的隐私边界，明确区分"用户自有数据可检索"与"受保护信息不可泄露"：

- Spark 不再以隐私为由拒绝返回用户自己的拍记内容
- 更新隐私同意书文案，新增"联网读取需授权"条目

## Spark 对话体验优化

- **终止回复**：AI 生成过程中，发送键变为停止键，可随时中断回复
- **Agent 首轮对话标题修复**：修复首轮对话标题显示异常的问题
- **发送键样式优化**：改为单层实心玻璃按钮，视觉更清爽
- **标题位置调整**：对话标题移至内容区 header，避免 toolbar 截断

## 模型与思考切换器

Spark 新增独立的模型和思考强度选择器：

- **模型选择胶囊**（SparkModelChip）：在对话界面快速切换 AI 模型
- **思考强度控制**（ThinkingCapability）：支持 per-provider 思考参数注入，可调节模型思考深度
- **持久化偏好**：SparkModelPreferences 独立保存模型和思考强度设置，不影响全局配置
- **预设模型列表刷新**：更新至 2026-06 最新模型 ID

## RAG 语义检索

为 Spark Agent 的拍记搜索带来语义理解能力，不再局限于关键词匹配：

- **端侧向量引擎**：默认使用 Apple NLEmbedding 在设备本地计算语义向量，完全离线、不外传数据
- **混合排序**（SemanticRanker）：关键词命中始终优先，语义相似结果按阈值纳入，兼顾精确与模糊搜索
- **懒补算 + 缓存**：搜索时自动为缺失向量的拍记补算并缓存，无需预处理
- **云端检索（可选）**：在实验室中可开启"高质量云端检索"，使用你配置的 AI 服务商 Embedding 接口，检索更精准
- **降级机制**：向量计算失败时自动退化为关键词搜索，保证搜索始终可用

## 全量待办管理

- **AllTodosView**：新增完整的待办管理页面，按截止日分桶显示（已逾期 / 今天 / 明天 / 本周 / 更晚 / 无截止日期）
- **Today 概览精简**：Today 页只显示当下可执行的待办（逾期 + 今天 + 无截止），封顶 5 条
- **多入口**：Today 待办计数徽章可点击进入 AllTodosView，「我」页新增"所有待办"入口

## 记录来源区分

拍记现在支持三种来源，各有专属视觉标识：

- **拍照记录**（photo）：原有拍照/相册导入的拍记，显示照片缩略图
- **Spark 生成**（spark）：Agent 创建的记录，显示 sparkles 渐变图标缩略图，无图片预览
- **纯文字记录**（text）：手动创建的文字记录，显示 doc.text 图标缩略图

## "Spark 生成"文件夹

Agent 创建的拍记自动归入专属的"Spark 生成"文件夹：

- 文件夹显示在日程文件夹区域，带 sparkles 图标
- 不出现在自建文件夹列表中
- NoteCreateTool 自动标记 `.spark` 来源并归入文件夹

## Spark 历史对话搜索

历史对话列表新增搜索功能，支持按标题和消息内容搜索，快速找到之前的对话。

## Today 独立玻璃圆按钮

- Today 页头像和加号按钮改为独立圆形玻璃按钮
- 头像与登录状态同步，登录后显示用户头像

## iOS 26 Liquid Glass 适配

全面适配 iOS 26 新的 Liquid Glass 设计语言，同时保持 iOS 18–25 的兼容回退：

- **GlassStyle 适配层**：集中封装 `glassIconButton` / `glassSurface` / `AdaptiveGlassContainer`
- **Today**：头像和加号按钮玻璃化（加号为 prominent accent 玻璃）
- **Spark**：新建/历史按钮、输入栏背景、发送按钮、Agent chip、重试 chip 玻璃化
- **相机**：闪光灯、变焦预设、文件夹按钮、单拍/连拍切换胶囊玻璃化
- **Tab Bar**：确认自动玻璃化，无需额外处理

## AI 调用健壮性

- **callAgent 解析增强**：容忍 AI 服务商返回的非标准响应格式，减少解析失败
- **OpenAICaller.callEmbedding**：新增 Embedding API 调用方法，支持 OpenAI 兼容接口

## 技术细节

| 项目 | 说明 |
|------|------|
| 新增文件 | GlassStyle.swift, UserProfile.swift, AccountStore.swift, LocalLoginView.swift, ProfileEditView.swift, ThinkingCapability.swift, SparkModelPreferences.swift, SparkModelChip.swift, WebFetchTool.swift, DateInfoTool.swift, ScheduleUpdateTool.swift, VectorMath.swift, EmbeddingService.swift, EmbeddingIndex.swift, SemanticRanker.swift, LocalEmbeddingService.swift, CloudEmbeddingService.swift, HybridEmbeddingService.swift, SemanticSearchEngine.swift, TodoBucketer.swift, AllTodosView.swift |
| 修改文件 | NoteRecord.swift（新增 RecordSource 枚举）, NoteSearchTool.swift（接入语义引擎）, NoteCreateTool.swift（标记 .spark + 归入文件夹）, SparkViewModel.swift（装配语义引擎 + 模型偏好 + folderTagManager）, SparkInputBar.swift, SparkView.swift, SparkHistoryView.swift, SparkPrivacySheet.swift, TodayView.swift, TodayViewModel.swift, MeView.swift, RecordsView.swift, RecordThumbnailView.swift, RecordDetailView.swift, FolderTagManager.swift, LabFeaturesView.swift, AIAPIClient.swift（新增 callEmbedding）, CaptureView.swift |
| 第三方依赖 | 无变化（仍为 ZIPFoundation, MarkdownUI, OnboardingKit, WhatsNewKit, lottie-ios） |
| 系统权限 | 无新增 |
| 向后兼容 | RecordSource 使用自定义 Codable 解码，旧数据缺失 source 字段时默认为 .photo |
