# iOS 26 Liquid Glass 控件层适配 — 设计方案

| 字段 | 值 |
|------|-----|
| 文档版本 | 1.0 |
| 创建日期 | 2026-06-20 |
| 所属产品 | Notiee |
| 分支 | feature/ai-agent |
| 构建环境 | Xcode 26.5（iOS 26 SDK），部署目标 iOS 18.0 |

---

## 一、背景与目标

把 Notiee 的**控件/导航层**按钮与浮层适配 iOS 26 的 Liquid Glass 设计语言，同时**保留 iOS 18–25 的兼容回退**。玻璃只用于浮在内容之上的控件，内容层保持不透明（遵循 Apple HIG，避免过度玻璃化）。

### 关键约束
- 部署目标 **iOS 18.0**，但用 **Xcode 26.5 / iOS 26 SDK** 构建。
- 玻璃 API（`glassEffect`、`buttonStyle(.glass)`/`.glassProminent`、`GlassEffectContainer`）均 **iOS 26 only**，必须用 `if #available(iOS 26, *)` 门控 + 旧样式兜底。
- 标准 `TabView`（`RootTabView.swift`）在 iOS 26 上**自动**获得 Liquid Glass 浮动 tab bar，零代码，无需改动（只需确认未设置 `UIDesignRequiresCompatibility` 退回旧样式）。

---

## 二、决策记录

| 决策点 | 选择 |
|--------|------|
| 兼容策略 | 保留 iOS 18 目标 + 可用性门控（集中式复用封装） |
| 范围 | 你点名的 4 个按钮 + 控件层（相机悬浮控件、Spark 输入栏与浮动 chip）；Tab bar 自动免费 |

---

## 三、架构：集中式自适应玻璃封装

新增 `Notiee/Utils/GlassStyle.swift`，把「iOS 26 用玻璃 / 低版本回退」的判断封装一次，调用处保持干净。单一真相源——以后 API 变动或回退样式调整只改这一个文件。

```swift
import SwiftUI

extension View {
    /// 图标按钮：iOS 26 用玻璃按钮样式，低版本保持原样（裸图标 + tint）。
    @ViewBuilder func glassIconButton(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(prominent ? .glassProminent : .glass)
        } else {
            self
        }
    }

    /// 浮层表面（输入栏 / chip / 胶囊）：iOS 26 用 glassEffect，低版本用 ultraThinMaterial。
    @ViewBuilder func glassSurface<S: Shape>(in shape: S, prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(prominent ? .regular.tint(.accentColor) : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// 相邻玻璃元素的融合容器（iOS 26 用 GlassEffectContainer，低版本透传）。
struct AdaptiveGlassContainer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}
```

> 备注：`glassSurface` 的 prominent 分支用 `.regular.tint(.accentColor)`；若该链式 API 在 26.5 SDK 中签名不同，以真实 API 为准（核心要求：iOS 26 走 `glassEffect`，低版本走 `ultraThinMaterial`）。`buttonStyle(.glass)` 会给图标套玻璃背景，因此调用处图标尺寸/内边距需微调以在胶囊内居中。

> 备选方案（已否决）：在每个按钮内联 `if #available` → 重复、分散、回退逻辑无法集中维护。

---

## 四、逐目标应用清单

### A. 点名的 4 个按钮

| 目标 | 位置 | 改法 |
|------|------|------|
| Today 头像 `person.crop.circle` | `Features/Today/TodayView.swift:134` | `.glassIconButton()`（次要） |
| Today 加号 `plus.circle.fill` | `Features/Today/TodayView.swift:143` | `.glassIconButton(prominent: true)`（主操作） |
| Spark 新建对话 `square.and.pencil` | `Features/Spark/SparkView.swift` headerView | `.glassIconButton()` |
| Spark 历史 `clock.arrow.circlepath` | `Features/Spark/SparkView.swift` headerView | `.glassIconButton()` |

- Today 头像 + 加号用 `AdaptiveGlassContainer` 包住，使两者在 iOS 26 上融合。
- Spark 新建 + 历史用 `AdaptiveGlassContainer` 包住。
- 图标改用玻璃按钮后，去掉/调整原 `NotieeColors.themed(.blue)` 直接着色，改用 `.tint(...)` 让玻璃样式接管前景；尺寸从 size:30/17 视玻璃胶囊效果微调。

### B. 控件层

| 目标 | 位置 | 改法 |
|------|------|------|
| Spark 输入栏（现 `.ultraThinMaterial` 圆角 26） | `Features/Spark/SparkInputBar.swift` | 背景换 `glassSurface(in: RoundedRectangle(cornerRadius: 26))` |
| Spark 发送按钮（实心圆 arrow.up） | `Features/Spark/SparkInputBar.swift` | `.glassIconButton(prominent: true)` |
| 浮动 Agent chip | `Features/Spark/SparkAgentChip.swift` | 背景换 `glassSurface(in: RoundedRectangle(cornerRadius: 12))`（保留开/关两态语义，开启态用 prominent/tint） |
| 「用 Agent 模式重试」chip | `Features/Spark/SparkView.swift` | 背景换 `glassSurface(in: RoundedRectangle(cornerRadius: 14))` |
| 相机：闪光按钮 | `Features/Capture/CaptureView.swift` | `glassSurface(in: Circle())` / `glassIconButton` |
| 相机：变焦预设胶囊 | `Features/Capture/CaptureView.swift` | `glassSurface(in: Capsule())` 替换 `Color.black.opacity(0.6)` |
| 相机：文件夹按钮、单拍/连拍切换 | `Features/Capture/CaptureView.swift` | `glassSurface` / `glassIconButton` |
| 相机整组悬浮控件 | `Features/Capture/CaptureView.swift` | 用 `AdaptiveGlassContainer` 包住融合 |
| 相机快门（英雄控件） | `Features/Capture/CaptureView.swift` | 保持基本不变，最多加玻璃描边（不强制） |

### C. 免费 / 验证项

- Tab bar：iOS 26 自动玻璃，**不改代码**。验证：确认工程未设置 `UIDesignRequiresCompatibility`（已初步确认未设置）。

---

## 五、验证策略

玻璃是纯视觉效果，无法单元测试外观。验证 = 两条路径：

1. **iOS 26 模拟器（iPhone 17 Pro）build + 运行**：肉眼确认 4 按钮、输入栏、chip、相机控件呈玻璃质感；tab bar 自动玻璃。
2. **回退路径确认**：封装的 `#available` 分支在低版本走 `ultraThinMaterial` / 裸图标，确保编译通过且不崩（可通过 Preview 或将某处临时降级验证逻辑分支）。

封装内部的可用性分支逻辑无需单测（纯条件分发）。每处改动以 `xcodebuild build` 通过为门槛。

---

## 六、影响文件清单

| 文件 | 变更 |
|------|------|
| `Notiee/Utils/GlassStyle.swift` | 新增（封装） |
| `Notiee/Features/Today/TodayView.swift` | 头像 + 加号按钮 |
| `Notiee/Features/Spark/SparkView.swift` | 新建/历史按钮 + 重试 chip |
| `Notiee/Features/Spark/SparkInputBar.swift` | 输入栏背景 + 发送按钮 |
| `Notiee/Features/Spark/SparkAgentChip.swift` | chip 背景 |
| `Notiee/Features/Capture/CaptureView.swift` | 相机悬浮控件组 |

---

## 七、非目标（Out of Scope）

- 不抬高部署目标（保留 iOS 18）。
- 不把内容层（列表行、卡片、详情正文）玻璃化。
- 不重构 tab bar（自动获得玻璃）。
- 不改 `RecordDetailView` / `RecordsView` / `Settings` 等其余 material 处（本轮范围之外，可后续单独评估）。
