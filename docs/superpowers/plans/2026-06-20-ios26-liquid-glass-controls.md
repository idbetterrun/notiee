# iOS 26 Liquid Glass 控件层适配 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Notiee 控件层（Today 头像/加号、Spark 新建/历史、Spark 输入栏与浮动 chip、相机悬浮控件）适配 iOS 26 Liquid Glass，保留 iOS 18–25 兼容回退。

**Architecture:** 新增 `Notiee/Utils/GlassStyle.swift` 集中封装 `if #available(iOS 26,*)` 玻璃/回退判断（`glassIconButton`、`glassSurface(in:)`、`AdaptiveGlassContainer`），调用处只加一行。纯 UI，验证靠 iOS 26 模拟器 build + 肉眼，无单测。

**Tech Stack:** SwiftUI / iOS 26 SDK（Xcode 26.5）/ 部署目标 iOS 18.0。玻璃 API：`buttonStyle(.glass)`/`.glassProminent`、`glassEffect(_:in:)`、`GlassEffectContainer`（均 iOS 26 only）。

**对应 spec:** `docs/superpowers/specs/2026-06-20-ios26-liquid-glass-controls-design.md`

---

## 通用命令

模拟器用 **iPhone 17 Pro**（iOS 26，已启动）。本计划无单测，每步以 build 通过为门槛：
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
> 注意：所有玻璃 API 必须在 `if #available(iOS 26, *)` 内调用。直接裸用会因部署目标 iOS 18 编译失败——这正是封装存在的原因。新建的 `.swift` 文件需加入 Notiee target（仓库用显式 pbxproj 引用；mirror 现有源文件的 PBXFileReference/PBXBuildFile/group/Sources 四处注册，或确认 Xcode 已勾选 target membership）。

---

## 文件结构总览

| 文件 | 创建/修改 | 任务 |
|------|-----------|------|
| `Notiee/Utils/GlassStyle.swift` | 创建（封装） | 1 |
| `Notiee/Features/Spark/SparkView.swift` | 修改（新建/历史按钮、重试 chip） | 2, 5 |
| `Notiee/Features/Today/TodayView.swift` | 修改（头像、加号） | 3 |
| `Notiee/Features/Spark/SparkInputBar.swift` | 修改（输入栏背景、发送按钮） | 4 |
| `Notiee/Features/Spark/SparkAgentChip.swift` | 修改（chip 背景） | 5 |
| `Notiee/Features/Capture/CaptureView.swift` | 修改（相机悬浮控件） | 6 |
| 工程设置确认 | — | 7 |

---

## Task 1: 创建 GlassStyle 封装

**Files:**
- Create: `Notiee/Utils/GlassStyle.swift`

- [ ] **Step 1: 创建封装文件**

```swift
import SwiftUI

extension View {
    /// 图标按钮：iOS 26 用玻璃按钮样式，低版本保持原样（裸图标 + tint）。
    /// 应用在 `Button { } label: { ... }` 上。
    @ViewBuilder
    func glassIconButton(prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self
        }
    }

    /// 浮层表面（输入栏 / chip / 胶囊）：iOS 26 用 glassEffect，低版本用 ultraThinMaterial。
    @ViewBuilder
    func glassSurface<S: Shape>(in shape: S, prominent: Bool = false) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                self.glassEffect(.regular.tint(.accentColor), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

/// 相邻玻璃元素的融合容器：iOS 26 用 GlassEffectContainer，低版本透传。
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

- [ ] **Step 2: 注册到 Notiee target + build**

把 `GlassStyle.swift` 加入 Notiee target（pbxproj 四处，mirror 如 `Utils/Logger.swift` 的注册），然后：
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

> 若 `.glassEffect(.regular.tint(.accentColor), in:)` 或 `GlassEffectContainer { }` 的真实签名与上面不符（以 iOS 26.5 SDK 为准），调整到能编译的等价写法；核心不变：iOS 26 走玻璃、低版本走 `ultraThinMaterial`/裸图标。可在 Xcode 里对 `GlassEffectContainer`、`glassEffect`、`buttonStyle(.glass)` 按住 Cmd 点进去看真实声明。

- [ ] **Step 3: Commit**
```bash
git add Notiee/Utils/GlassStyle.swift Notiee.xcodeproj/project.pbxproj
git commit -m "feat(ui): add adaptive Liquid Glass helpers (iOS 26 with iOS 18 fallback)"
```

---

## Task 2: Spark 头部 — 新建对话 + 历史按钮玻璃化

**Files:**
- Modify: `Notiee/Features/Spark/SparkView.swift`（headerView 里的两个按钮）

- [ ] **Step 1: 读取并定位**

打开 `SparkView.swift` 的 `headerView`，找到这两个相邻按钮（新建对话 `square.and.pencil` + 历史 `clock.arrow.circlepath`），当前形如：
```swift
            Button {
                viewModel.newConversation()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NotieeColors.themed(.blue))
            }

            Button {
                activeSheet = .history
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NotieeColors.themed(.blue))
            }
            .padding(.leading, 16)
```

- [ ] **Step 2: 包进 AdaptiveGlassContainer 并加玻璃按钮样式**

替换为（用容器包住两个按钮使其在 iOS 26 融合；各自加 `.glassIconButton()`；历史按钮原 `.padding(.leading, 16)` 改成容器内 HStack 的 spacing）：
```swift
            AdaptiveGlassContainer {
                HStack(spacing: 12) {
                    Button {
                        viewModel.newConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(NotieeColors.themed(.blue))
                    }
                    .glassIconButton()

                    Button {
                        activeSheet = .history
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(NotieeColors.themed(.blue))
                    }
                    .glassIconButton()
                }
            }
```
读取真实代码后精确替换，保持 headerView 外层 `HStack`/`Spacer` 结构有效。

- [ ] **Step 3: Build**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`
（运行 iOS 26 模拟器进 Spark，肉眼确认两个按钮呈玻璃胶囊。）

- [ ] **Step 4: Commit**
```bash
git add Notiee/Features/Spark/SparkView.swift
git commit -m "feat(spark): glass header buttons (new conversation, history)"
```

---

## Task 3: Today 头部 — 头像 + 加号玻璃化

**Files:**
- Modify: `Notiee/Features/Today/TodayView.swift`（头像 NavigationLink + 加号 Button，约 130–146 行）

- [ ] **Step 1: 读取并定位**

当前形如：
```swift
            if let store = viewModel.store {
                NavigationLink {
                    MeView(settingsStore: UserDefaultsAppSettingsStore.live, store: store)
                } label: {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(NotieeColors.themed(.blue))
                }
            }

            Button {
                showCreateSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(NotieeColors.themed(.blue))
            }
```

- [ ] **Step 2: 包容器 + 玻璃样式（加号用 prominent）**

替换为：
```swift
            AdaptiveGlassContainer {
                HStack(spacing: 12) {
                    if let store = viewModel.store {
                        NavigationLink {
                            MeView(settingsStore: UserDefaultsAppSettingsStore.live, store: store)
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 26))
                                .foregroundStyle(NotieeColors.themed(.blue))
                        }
                        .glassIconButton()
                    }

                    Button {
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .glassIconButton(prominent: true)
                }
            }
```
说明：加号改主操作 `prominent`（玻璃 accent 胶囊），图标从 `plus.circle.fill` 换成裸 `plus`（玻璃胶囊自带背景，避免双重圆形），去掉显式蓝色让 prominent 玻璃接管前景；头像图标尺寸 30→26 适配玻璃胶囊。读取真实代码后精确替换。

- [ ] **Step 3: Build**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`
（iOS 26 模拟器进 Today，确认头像玻璃、加号 accent 玻璃。若加号前景在玻璃上偏暗，给 `Button` 加 `.tint(.white)` 或 `.foregroundStyle(.white)`。）

- [ ] **Step 4: Commit**
```bash
git add Notiee/Features/Today/TodayView.swift
git commit -m "feat(today): glass avatar and prominent glass add button"
```

---

## Task 4: Spark 输入栏 — 背景表面 + 发送按钮

**Files:**
- Modify: `Notiee/Features/Spark/SparkInputBar.swift`

- [ ] **Step 1: 输入栏背景换 glassSurface**

`SparkInputBar` 的整条背景当前是：
```swift
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.5)
        )
```
把 `.background(RoundedRectangle(...).fill(.ultraThinMaterial))` 改为 `glassSurface`：
```swift
        .glassSurface(in: RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color(.separator).opacity(0.12), lineWidth: 0.5)
        )
```
（`glassSurface` 在低版本回退到 `.background(.ultraThinMaterial, in:)`，与原效果一致。）

- [ ] **Step 2: 发送按钮改 prominent 玻璃**

发送按钮当前是 `Button(action: onSubmit) { ... Circle().fill(accentColor or systemGray4) ... }`。读取真实代码，把它的圆形实心背景交给玻璃：给该 `Button` 末尾加 `.glassIconButton(prominent: true)`，并移除 label 里手画的 `.background(Circle().fill(...))`（玻璃胶囊替代）。保留 disabled 逻辑与 `arrow.up`/ProgressView 切换。若移除手画圆形后空态/禁用态视觉不佳，保留一个浅色 Circle 作 disabled 兜底，仅在 enabled 时套玻璃——以编译通过 + 视觉合理为准。

- [ ] **Step 3: Build**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**
```bash
git add Notiee/Features/Spark/SparkInputBar.swift
git commit -m "feat(spark): glass input bar surface and send button"
```

---

## Task 5: 浮动 chip 玻璃化（Agent chip + 重试 chip）

**Files:**
- Modify: `Notiee/Features/Spark/SparkAgentChip.swift`
- Modify: `Notiee/Features/Spark/SparkView.swift`（「用 Agent 模式重试」chip）

- [ ] **Step 1: SparkAgentChip 背景换 glassSurface**

当前 `SparkAgentChip` 的 label 背景：
```swift
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isOn ? Color.purple : Color.gray.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? Color.clear : Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
```
开启态保持纯色高亮（语义重要，别让玻璃稀释「开」的存在感），关闭态用玻璃：
```swift
            .glassSurface(in: RoundedRectangle(cornerRadius: 12), prominent: isOn)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isOn ? Color.clear : Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
```
（`prominent: isOn` → 开启态 accent-tinted 玻璃，关闭态普通玻璃；前景 `isOn ? .white : .secondary` 保持不变。读取真实代码精确替换那段 `.background(...)`。）

- [ ] **Step 2: 重试 chip 背景换 glassSurface**

`SparkView.swift` 里「用 Agent 模式重试」chip 的 label 背景当前：
```swift
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(Color.purple.opacity(0.12))
                                    )
```
改为：
```swift
                                    .glassSurface(in: RoundedRectangle(cornerRadius: 14))
```

- [ ] **Step 3: Build**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**
```bash
git add Notiee/Features/Spark/SparkAgentChip.swift Notiee/Features/Spark/SparkView.swift
git commit -m "feat(spark): glass floating chips (Agent toggle, retry suggestion)"
```

---

## Task 6: 相机悬浮控件玻璃化

**Files:**
- Modify: `Notiee/Features/Capture/CaptureView.swift`

相机控件浮在取景画面之上，是玻璃语言的头号场景。

- [ ] **Step 1: 读取并定位悬浮控件**

打开 `CaptureView.swift`，定位这些控件的不透明背景（grep 锚点）：
- 闪光按钮：`.background(... ? Color.yellow : Color.white.opacity(0.15), in: Circle())`（约 102 行）
- 变焦预设胶囊：`Capsule()` + `Color.black.opacity(0.6)`（约 263–266 行）
- 文件夹按钮：`.background(Color.white, in: Circle())`（约 221 行）
- 单拍/连拍切换胶囊：`.background(Color.black.opacity(0.6), in: Capsule())`（约 375 行）

- [ ] **Step 2: 逐个把不透明背景替换为 glassSurface**

对上面每处，把 `.background(<纯色>, in: <shape>)` 改为 `.glassSurface(in: <shape>)`（形状保持 Circle()/Capsule() 不变）。示例：
```swift
// 变焦预设胶囊 before:
        .background(
            Capsule()
                ...
                .background(Color.black.opacity(0.6))
        )
// after:
        .glassSurface(in: Capsule())
```
```swift
// 单拍/连拍 before:
        .background(Color.black.opacity(0.6), in: Capsule())
        .overlay(Capsule().stroke(Color.white, lineWidth: 1))
// after:
        .glassSurface(in: Capsule())
        .overlay(Capsule().stroke(Color.white, lineWidth: 1))
```
闪光/文件夹按钮的圆形纯色背景同理换 `.glassSurface(in: Circle())`（闪光「开」态可保留黄色高亮：`isOn ? Color.yellow.background... : .glassSurface`，以语义清晰为准）。
**快门主控件不动**（英雄控件保留实心）。读取真实代码逐处精确替换，保持各控件的 `Image`/前景色/点击逻辑不变。

- [ ] **Step 3:（可选）相机控件组用容器融合**

若多个玻璃控件相邻（如变焦预设 + 闪光），可把该簇包进 `AdaptiveGlassContainer { ... }` 让 iOS 26 融合。仅在不破坏现有布局的前提下做；不确定就跳过。

- [ ] **Step 4: Build**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -25
```
Expected: `** BUILD SUCCEEDED **`
（注意：相机在模拟器无真实取景，玻璃效果以深色背景近似确认；真机更准。）

- [ ] **Step 5: Commit**
```bash
git add Notiee/Features/Capture/CaptureView.swift
git commit -m "feat(capture): glass floating camera controls (flash, zoom, folder, burst)"
```

---

## Task 7: Tab bar 确认 + 全量 build + 视觉冒烟

**Files:**
- 只读确认 `Notiee/Info.plist` / target 设置

- [ ] **Step 1: 确认未退回旧 tab bar 样式**

确认工程未设置退回旧设计的开关（设置了会让 iOS 26 不自动玻璃化）：
```bash
grep -rn "UIDesignRequiresCompatibility" Notiee/ Notiee.xcodeproj/ || echo "  -> 未设置（好，tab bar 自动玻璃）"
```
Expected: 无匹配（即未退回）。若存在且为 true，与用户确认是否移除（本计划默认保持自动玻璃）。

- [ ] **Step 2: 全量 build**
```bash
xcodebuild build -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: iOS 26 模拟器视觉冒烟清单**

运行 App，逐项肉眼确认：
- [ ] 底部 tab bar：浮动玻璃（自动）
- [ ] Today：头像玻璃、加号 accent 玻璃
- [ ] Spark：新建/历史玻璃、输入栏玻璃、发送按钮玻璃、Agent chip（开/关两态清晰）、重试 chip 玻璃
- [ ] 相机：闪光/变焦/文件夹/单拍连拍玻璃，快门不变
- [ ]（可选）若有 iOS 18 模拟器，确认回退：裸图标 + ultraThinMaterial，无崩溃

- [ ] **Step 4:（如有未提交改动）Commit**
```bash
git add -A && git commit -m "chore(ui): verify tab bar auto-glass and full glass smoke pass" || echo "nothing to commit"
```

---

## 自审备注（spec 覆盖核对）

| spec 项 | 覆盖任务 |
|---------|----------|
| 集中式封装（glassIconButton/glassSurface/AdaptiveGlassContainer） | Task 1 |
| Today 头像 + 加号 | Task 3 |
| Spark 新建 + 历史 | Task 2 |
| Spark 输入栏 + 发送按钮 | Task 4 |
| 浮动 Agent chip + 重试 chip | Task 5 |
| 相机悬浮控件 | Task 6 |
| Tab bar 自动玻璃确认 + 冒烟 | Task 7 |
| iOS 18 兼容门控 | Task 1 封装 + 各任务沿用 |
