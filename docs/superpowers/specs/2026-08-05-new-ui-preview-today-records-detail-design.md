# NewUIPreview Today、记录与记录详情设计规格

| 字段 | 值 |
| --- | --- |
| 日期 | 2026-08-05 |
| 状态 | 已确认的设计方向；尚未实施 |
| Target | Notiee 与 Notiee+ |
| 实施范围 | `Notiee/Features/Settings/NewUIPreview/` |
| 数据范围 | 仅 mock 数据，不连接 `NotieeStore` |

## 1. 目标

在实验室的 `NewUIPreview` 中完整预演下一代 Today、记录库和记录详情体验：

- Today 在第一秒回答“现在最重要的是什么”，同时提供完整模块入口和当天内容切换。
- 记录库改为适合图片、文字混合内容的双列瀑布流。
- 记录详情改为长文档阅读体验，清晰区分整理内容、原文和待办。
- 参考外部截图的信息架构、空间关系和滚动行为，但最终视觉统一采用 iOS 26 原生 Liquid Glass。

本规格只定义实验预览。它不修改正式 Today、`RecordsView`、`RecordDetailView`、持久化模型、后端或两 target 的传输路径。

## 2. 与现有规格的关系

本规格建立在以下文档之上：

- `2026-07-29-today-2-context-dashboard-design.md`
- `2026-07-29-new-ui-preview-active-event-aurora-design.md`
- `2026-06-20-ios26-liquid-glass-controls-design.md`

对 `NewUIPreview` 而言，本规格做如下更新：

- 保留 Today 的确定性 Hero 优先级、固定屏、上下捕获手势和底部 Today / Spark / Records 导航。
- 保留 active-event Aurora 的可见性、颜色和生命周期规则。
- 用“模块快捷入口 + 今日标签内容”替换现有预览中的 urgent slot、adaptive review slot 和 statistics slot。
- 增加可滚动的 Records 目的地和记录详情原型。
- Liquid Glass 仍只用于控件/导航层，内容层保持清晰、稳定。

正式 Today 2.0 的生产实施计划不因本预览规格自动变更。只有预览验证并另行批准后，才讨论迁移到正式页面。

## 3. 范围与 Target 分类

### 3.1 Target 分类

- 分类：**同时影响 Notiee 与 Notiee+**。
- 所有新 Swift 文件只属于 `NewUIPreview`，并加入两个 App target。
- 不使用 `#if NOTIEE_PLUS`，因为本阶段没有 target 特有行为。
- 不调用免费版后端，也不调用 Notiee+ 的 BYOK 模型服务。

### 3.2 本阶段包含

- Today 新布局和 mock 场景切换。
- Today 模块快捷入口和今日标签切换。
- Records 搜索、mock 过滤、瀑布流和记录卡片变体。
- Records -> Record Detail 的本地预览导航。
- Record Detail 的媒体、吸顶导航、正文、原文、待办和浮动动作原型。
- Liquid Glass、浅色/深色、Dynamic Type、Reduce Motion、Reduce Transparency 的视觉验证。

### 3.3 本阶段不包含

- 正式 `NotieeStore` 数据接入。
- 正式 Today、Records 或 Record Detail 文件改造。
- 新的持久化字段或迁移。
- 真正保存“追加记录”。
- 真正生成“涌现”报告。
- 后端、订阅、配额、模型或 Keychain 变更。

## 4. 全局视觉语言：iOS 26 Liquid Glass

参考截图只决定布局和层级，不决定材质与配色。最终预览必须使用 Notiee 的系统语义色和 iOS 26 Liquid Glass。

### 4.1 使用 Glass 的区域

- 顶部工具栏和图标按钮。
- 搜索框。
- Today 的三个模块快捷入口。
- Today 的分段标签。
- Records 的筛选/搜索控件。
- Record Detail 的吸顶导航。
- 条件出现的返回顶部按钮。
- Record Detail 的底部“追加记录 / 涌现”动作栏。
- 持久的 Today / Spark / Records 底部 Dock。

### 4.2 不使用 Glass 的区域

- 照片和多图拼贴。
- Records 瀑布流卡片的正文表面。
- Record Detail 的标题、元数据和长文档正文。
- 空状态正文。
- Aurora 本身。

内容不能因为 Glass 变模糊、降低对比度或产生多层嵌套卡片。Glass 是浮在内容上的控件层，不是页面背景。

### 4.3 控件实现约束

- 相邻 Glass 控件在适合的场景使用原生 `GlassEffectContainer` 分组。
- 每个可见控件必须有稳定宽高和与外形一致的 `contentShape`。
- 点击区域至少 44 x 44 pt，并覆盖整个可见 Glass 表面。
- 不在独立背景层上添加 Glass 后再覆盖文字；材质应属于控件的可见表面。
- 选中态通过 tint、前景色和原生 Glass 反馈表达，不叠加第二张实心卡片。
- Reduce Transparency 下使用更不透明的语义表面，保证文字和图标对比度。
- 浅色、深色和跟随系统模式都必须可用。

## 5. 全局导航与状态

根视图仍为：

```text
Today | persistent Spark composer | Records
```

- Today 与 Records 是两个目的地。
- 中间 Spark 控件打开现有预览 Composer，不成为第三个 tab。
- Today 的“记录”快捷入口与底部 Records 均可进入 Records；这是有意保留的上下文入口。
- Records 卡片和 Today 的今日记录项均可打开同一个 mock Record Detail。
- Record Detail 为预览内部导航层；返回后保留 Records 的滚动、搜索和筛选状态。
- 实验室的退出菜单和场景切换器继续存在，但不是未来生产 UI 的组成部分。

## 6. Today 设计

### 6.1 页面职责

Today 仍是固定屏 Context Dashboard，不是无限列表。页面不纵向滚动，并保留下拉相机、上拉音频入口的手势所有权。

### 6.2 页面结构

```text
Unframed Hero headline
Hero factual status

[ Records ] [ Todos ] [ Schedule ]   complete-module shortcuts

Today
[ Records | Todos | Schedule ]       local switcher
up to three daily items

Today / Spark / Records Dock
```

### 6.3 Hero

- 移除现有 Hero 左侧图标、圆形图标底和大圆角背景卡。
- 不使用吉祥物。
- 标题直接位于系统背景之上，左对齐，最多两行。
- 标题建议使用 30-32 pt 的粗体层级；不随视口宽度缩放字体。
- 标题下方是一行更轻的事实信息，例如时间、截止点、剩余时长或今日记录数。
- 不增加顶部 AI 搜索框；底部 Spark 已是持续的 AI 入口。

Hero 文案保持自然、简短、可确定生成，例如：

- Active event：`产品周会正在进行，接下来 25 分钟先留给它。`
- Due todo：`回复设计 review，今晚该收尾了。`
- Imminent event：`和导师的 1:1，15 分钟后开始。`
- Record momentum：`今天已经留下 3 条记录。`
- Calm：`现在很安静，今天还没有新的记录。`

### 6.4 Active-event Aurora

- 只在 `.activeEvent` 显示。
- 位于 Hero 文本背后，不形成矩形容器。
- 延续现有 tag color 与 Notiee green fallback 规则。
- 因 Hero 卡背景被移除，应重新校准 Aurora 不透明度，确保浅色与深色模式下标题对比度达标。
- Aurora 不接收触摸；Reduce Motion 下冻结稳定帧。

### 6.5 三个模块快捷入口

快捷入口顺序固定为：

```text
记录 | 待办 | 日程
```

- 三个入口同宽、同高，可显示 SF Symbol、名称和简短数量。
- 它们代表完整模块，不只代表今天。
- 记录入口切换到 Records 目的地。
- 待办和日程在预览中进入对应 mock 全量页或明确的预览占位层。
- 使用 Glass 控件外观，但避免在 Glass 内再嵌套卡片。

### 6.6 今日标签区

标签上方使用区块标题 `今天`，标签文字简写为：

```text
记录 | 待办 | 日程
```

“今天”的区块标题负责限定时间范围，不在每个标签里重复“今日”。

首次选择由 Hero 上下文决定：

| Hero context | 初始标签 |
| --- | --- |
| `.activeEvent` | 日程 |
| `.imminentEvent` | 日程 |
| `.dueTodo` | 待办 |
| `.recordMomentum` | 记录 |
| `.calm` | 记录 |

- 用户手动切换后，本次 Today 停留期间保持用户选择，不被 Hero 重新抢回。
- 标签通过点击切换，不支持左右滑动，避免与根捕获手势竞争。
- 每个标签最多展示三条。
- 无内容时显示一行轻量空状态，不显示空白大卡片。
- 不在标签内容内创建纵向 ScrollView；完整内容通过上方模块入口访问。

标签内容使用各自合适的表现：

- 记录：缩略图、标题和短摘要。
- 待办：完成状态、标题、截止时间。
- 日程：开始时间、标题、持续时间或进行状态。

### 6.7 捕获手势

- 保留现有下拉相机、上拉音频状态机。
- Today 标签、快捷入口、Dock、Composer 或预览导航层正在交互时，根手势不得抢占控制。
- 标签内容不滚动是避免捕获手势冲突的关键约束。

## 7. Records 设计

### 7.1 页面结构

- 页面可纵向滚动。
- 顶部使用明确的大标题 `记录`，不使用参考产品的问候语作为目的地标题。
- 标题下方提供常驻搜索框，搜索 mock 记录的标题和摘要。
- 主体为真正的双列瀑布流。
- 底部 Today / Spark / Records Dock 保持可见，并为最后一行内容预留安全间距。

### 7.2 瀑布流规则

- 两列等宽，卡片独立计算高度。
- 卡片按当前较短列分配；不能使用会让同一行按最高卡片对齐的普通 `LazyVGrid`。
- 数据顺序仍以最新记录优先，VoiceOver 顺序保持源数组顺序。
- 辅助功能大字号下自动切换为单列，避免标题、摘要和图片被压缩。
- 搜索结果、空状态和加载状态不能让底部 Dock 跳动。

### 7.3 卡片信息层级

```text
timestamp / processing state
title
summary
media
metadata
```

- 标题最多两行，尾部截断。
- 正文只读取 `NoteRecord.summary`。
- 摘要最多四行，尾部截断。
- 摘要为空时完全省略正文区域。
- 禁止以 `detailedContent` 或 `ocrText` 回填列表正文。
- 原始 OCR 和完整详细内容只在 Record Detail 展示。
- 元数据保持轻量，不在卡片底部堆叠大量 chip。

### 7.4 图片模板

| 图片数量 | Records 卡片表现 |
| --- | --- |
| 0 | 纯文本卡片，按标题和摘要自然长高 |
| 1 | 一张焦点图，保留主体并限制极端横竖比造成的高度 |
| 2 | 两张图片左右并列 |
| 3 | 一张主图 + 两张上下排列 |
| 4 | 2 x 2 拼贴 |
| 5+ | 2 x 2 拼贴，最后一格显示 `+N` |

- 多图必须真实加载并展示多张图片。
- 不沿用正式 `RecordThumbnailView` 当前“第一张图 + 灰色叠层”的提示方式。
- 图片为空且摘要为空时，卡片只保留时间/状态与标题，不制造大面积空白。
- 单图卡与多图卡允许拥有不同高度；这是瀑布流的重要组成部分。

### 7.5 特殊状态

- Encrypted：只显示锁和安全占位，不显示真实标题、摘要、图片或其他敏感内容。
- Pending/processing：显示稳定的处理状态和媒体占位，不闪烁重排。
- Failed：显示失败状态，但卡片仍可进入详情查看和重试入口原型。
- Text/Spark source：没有图片时使用纯文本模板，不伪造图片。

### 7.6 交互

- 点击卡片打开 mock Record Detail。
- 搜索实时过滤 mock 数据，并保持瀑布流布局稳定。
- 卡片本身不承载多个常驻小按钮；收藏、移动、删除等后续操作使用上下文菜单或详情页更多菜单。
- Records 的纵向滚动不触发 Today 的相机/音频手势。

## 8. Record Detail 设计

### 8.1 滚动层级

```text
fixed Glass toolbar

scrolling media
scrolling title / time / status / metadata
sticky Glass content selector
scrolling document body

conditional Glass scroll-to-top button
fixed Glass action dock
```

- 顶部工具栏保持固定。
- 图片、标题、时间、状态和元数据随正文滚走。
- 内容选择器到达工具栏下方后吸顶。
- 底部动作栏始终位于 safe area 上方。
- 正文底部 inset 必须大于动作栏高度，最后一段不能被遮挡。
- 用户滚动超过一个有意义的距离后显示返回顶部按钮；接近顶部时隐藏。

### 8.2 顶部工具栏

- 左侧：返回。
- 右侧：当前记录内搜索、分享、更多。
- 所有按钮使用原生 Liquid Glass 和 SF Symbols。
- 搜索只在当前记录的可见文本中查找并高亮，不是全记录库搜索。
- 更多菜单承载编辑、信息、加密和删除等低频操作的预览入口。

### 8.3 媒体

- 单图：一张大图作为 Hero，按图片比例展示并设置合理最大高度。
- 多图：全宽分页浏览，支持左右滑动、页码/数量反馈和单图全屏查看。
- 无图：直接从标题开始，不显示“无预览图片”占位。
- Records 的多图拼贴只属于概览；详情必须让每张图片可独立检查。

### 8.4 标题与元数据

- 标题是详情页第一主文本信号，允许自然换行，不缩成卡片标题字号。
- 标题下方显示创建时间和必要的处理状态。
- 元数据 chip 只来源于 Notiee 已拥有的字段：source、event、folder、processing state。
- 不为视觉完整而虚构 AI tag。

### 8.5 吸顶内容选择器

固定三个标签：

```text
整理内容 | 原文 | 待办
```

- `整理内容`：以文档形式组合 summary、detailed content、key points、definitions 以及必要的关联内容。
- `原文`：照片记录显示 OCR；其他来源只有在确实存在独立原文时才显示，否则给出轻量空状态。
- `待办`：显示从记录中提取或关联的待办；为空时显示轻量空状态。
- 标签使用 Glass 选中反馈，但下方正文不放进 Glass 容器。
- 标签切换保持当前页面上下文，不打开新的全屏目的地。

### 8.6 整理内容排版

- 页面是一张连续、无框的文档，不是多张嵌套卡片。
- 支持 Markdown 风格的标题、段落、有序/无序列表和强调。
- 正文字号、行高和段间距以长时间阅读为目标。
- 正文支持文字选择。
- Summary 可以作为导语，但不重复渲染相同的 detailed content。
- Key points 和 definitions 使用语义标题与列表，不使用装饰性渐变卡片。

### 8.7 底部动作

底部 Glass Dock 固定两个动作：

```text
追加记录 | 涌现
```

- 不使用吉祥物。
- `追加记录` 在预览中打开可关闭的 mock composer/sheet；本阶段不持久化。
- `涌现` 使用已批准的 Notiee 中文名称，不得出现 `发芽`。
- `涌现` 打开覆盖当前详情的浮动 sheet，不成为内容标签，也不替换详情页面。
- 该位置是 NewUIPreview 的视觉实验；正式生产入口位置仍需在预览验证后单独批准。

## 9. Mock 数据与预览状态

预览 fixtures 至少覆盖：

- Today 的五个 Hero context。
- 有/无 tag color 的 active event。
- 今日记录、今日待办、今日日程的有数据和空状态。
- 短纯文本记录。
- 长摘要记录。
- 单张横图记录。
- 单张竖图记录。
- 2、3、4、5+ 张图片记录。
- 无摘要记录。
- Pending、processing、failed 和 encrypted 记录。
- 有 OCR、无 OCR、有待办、无待办的详情。

所有 mock ID 必须稳定，避免视图刷新时重新生成 UUID 导致动画和导航状态跳动。

## 10. 建议组件边界

以下是实施时的建议，不要求本规格阶段创建文件：

| 文件/组件 | 职责 |
| --- | --- |
| `NewUIPreviewRootView.swift` | Today / Records / Detail 预览导航与实验室工具栏 |
| `NewUIPreviewState.swift` | 稳定 mock 数据、Hero、Today 标签、Records 搜索和导航状态 |
| `NewUIPreviewTodayView.swift` | 新 Hero、快捷入口和 Today 标签内容 |
| `NewUIPreviewRecordsView.swift` | Records 标题、搜索、瀑布流和空状态 |
| `NewUIPreviewMasonryLayout.swift` | 真正的较短列分配与 Dynamic Type 单列回退 |
| `NewUIPreviewRecordCard.swift` | 文本、单图、多图、加密和处理状态卡片 |
| `NewUIPreviewRecordMedia.swift` | Records 拼贴与 Detail pager 共用的图片加载/占位边界 |
| `NewUIPreviewRecordDetailView.swift` | 工具栏、媒体、元数据、吸顶标签、正文和浮动动作 |
| `NewUIPreviewGlass.swift` | 集中式 iOS 26 Glass 与无障碍回退 |
| `NewUIPreviewAuroraView.swift` | 保持现有 active-event Aurora 生命周期 |

生产 `RecordsView.swift`、`RecordThumbnailView.swift` 和 `RecordDetailView.swift` 不在本规格的实施文件清单中。

## 11. 无障碍与响应式要求

- 所有图标按钮有可理解的 accessibility label。
- 分段标签暴露选中状态。
- Record 卡片将标题、摘要、图片数量和状态组合为合理的 VoiceOver 顺序。
- 多图卡和详情 pager 应朗读 `第 X 张，共 Y 张`。
- Dynamic Type 较大时 Records 切换单列，文本不得与图标或图片重叠。
- Reduce Motion 下停止 Aurora 时间推进，并减少大范围转场。
- Reduce Transparency 下 Glass 控件提高不透明度和边界清晰度。
- 深色模式下图片、正文、Glass 和 Aurora 的层级必须仍然清楚。

## 12. 验收标准

### 12.1 Today

- Hero 无图标卡、无吉祥物、无白色矩形背景。
- 五个 Hero 场景的标题和事实行均不截断关键语义。
- Aurora 只出现在 active event，且不影响文字对比度与点击。
- 三个模块快捷入口可点击，顺序为记录 / 待办 / 日程。
- 今日标签首次跟随 Hero，手动切换后保持用户选择。
- 每个标签最多三条，页面不纵向滚动。
- 下拉相机、上拉音频和 Dock/标签点击不存在手势抢占。

### 12.2 Records

- 双列为真实瀑布流，不出现普通网格的整行空洞。
- 标题最多两行，摘要只取 `summary` 且最多四行。
- 摘要为空时不显示正文占位。
- 0、1、2、3、4、5+ 图模板均可辨认并稳定布局。
- 多图真实展示多张，不使用灰色叠层代替。
- 搜索、空状态、加密和处理状态均可预览。
- 大字号切换单列，底部 Dock 不遮住最后一张卡片。

### 12.3 Record Detail

- 单图大图、多图 pager、无图直达标题三种路径均正确。
- 工具栏固定，元数据随内容滚动，内容选择器吸顶。
- 整理内容为无框长文档，原文和待办可切换。
- 正文可选择，最后一段不被底部动作栏遮挡。
- 返回顶部按钮仅在滚动较深时出现并能回到顶部。
- `追加记录` 和 `涌现` 为 Glass 动作；页面没有吉祥物和 `发芽` 文案。
- `涌现` 打开浮动 sheet，关闭后仍停留在原详情上下文。

### 12.4 Target 与构建

- 所有新增 preview 文件加入 Notiee 与 Notiee+ target。
- 不添加 backend-only 依赖或 runtime 版本判断。
- 两个 scheme 均在 iPhone 17 模拟器构建通过。
- 在 iOS 26 模拟器或真机检查 Liquid Glass、浅色/深色、Reduce Motion、Reduce Transparency、Dynamic Type 和触摸区域。

## 13. 非目标

- 不在本阶段确定正式生产数据接入方案。
- 不实现无限滚动、分页数据库或图片缓存重构。
- 不改变 `NoteRecord` 编码格式。
- 不实现真正的追加记录持久化。
- 不实现真正的 Emergence 推理与报告生成。
- 不复制参考产品的升级按钮、吉祥物、白色实心浮层或底部 AI 输入栏。
- 不把所有内容表面玻璃化。
