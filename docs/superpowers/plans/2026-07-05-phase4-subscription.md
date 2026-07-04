# Phase 4: 订阅 / 内购（商业闭环）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让免费版用户能订阅 Notiee Pro（¥18/月），购买经 StoreKit 2 → 后端验签置档位 → 全 App 门控（Phase 2/2.5/3 已埋点）自动对 Pro 放开；付费墙满足 App 审核 3.1.2。

**Architecture:** 把 `CurrentEntitlement.tier` 从硬编码 `.free` 改成**持久化、可同步读**的真档位（`EntitlementStore` 写入）——这是让前几个 Phase 的门控「活起来」的总闸。新增 `StoreKitService`（StoreKit 2 购买/恢复/交易更新 → 上报后端 `/subscription/verify`）+ `PaywallView`（合规文案 + 恢复购买 + 法务链接）。三处占位 `alert` 换成统一 `paywallSheet`。后端把 `/subscription/verify` 与 `/apple/notifications` 从 stub 做实（App Store Server Library 验签 → 置 `users.tier` / `pro_expires_at`）。

**Tech Stack:** Swift / SwiftUI / StoreKit 2 / XCTest（客户端）；Node.js + `@apple/app-store-server-library`（后端 `notiee-ping-stream/`）；腾讯 SCF + MySQL；App Store Connect。

**已核对现状（Phase 0-3 已落）：**
- `CurrentEntitlement.tier` 仍是 `static var tier { .free }`（`Notiee/Models/CuratedModelCatalog.swift:77`）。
- `EntitlementStore`（`@MainActor`，`shared`/`quota`/`tier`/`refresh()`）已存在，`quota` 更新来自 `/me/quota` + `.backendQuotaUpdated` 广播。
- 三处付费墙触发点用占位 alert：`SparkView.swift:179`（`showProUpsell`）、`QuotaCard.swift:31`（`showProUpsell`）、`ModelPickerView.swift:24`（`showProAlert`）。
- `LegalDocument.bundleURL(base:)` + `LegalHTMLView(url:)` 可用（base：`UserAgreement`/`PrivacyPolicy`）。
- 后端 `store.setTier(userId, tier, proExpiresAt)`（memory+mysql 双实现）已存在；`/subscription/verify`（`verifyToken`，501 stub，index.js:443）、`/apple/notifications`（stub，:450）。
- 免费版 bundle id：`com.idbetterrun.notiee`。订阅产品 id 约定：`com.idbetterrun.notiee.pro.monthly`。

**隔离规则：**
- 新客户端文件 `StoreKitService.swift` / `PaywallView.swift` → **只勾 `Notiee` target**。
- `CurrentEntitlement`/`EntitlementStore` 是既有 [N] 文件，继续只在 Notiee。
- `SparkView`（共享）里引用 `PaywallView`（Notiee-only）**必须 `#if !NOTIEE_PLUS`**；`QuotaCard`/`ModelPickerView` 本就是 Notiee-only，直接引用即可。
- 客户端档位仅驱动 UI 解锁；**后端对每次 AI 调用二次校验**（`UPGRADE_REQUIRED`），改本地 UserDefaults 只能骗 UI、骗不到额度。

---

## Testing 说明

单测（Task 1）：
```bash
xcodebuild test -project Notiee.xcodeproj -scheme Notiee \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:NotieeTests/CurrentEntitlementTests
```
`xcodebuild` 报 `requires Xcode` 时先 `sudo xcode-select -s /Applications/Xcode.app`；或 Xcode `⌘U`。StoreKit 购买流程用 **StoreKit Configuration 文件**在模拟器本地测（Task 2），端到端 Pro 解锁需后端（Part B）+ 沙盒账号。

---

## 前置配置清单（非代码，需你在 Apple / 腾讯云侧完成）

> 这些不写进任务步骤，但 Part A/B 依赖它们。可与开发并行。

- [ ] **App Store Connect**：创建自动续期订阅群组 `Notiee Pro`，内含产品 **`com.idbetterrun.notiee.pro.monthly`**，时长 1 个月，价格选 ¥18 对应档；填本地化名称/描述。
- [ ] **Paid Apps Agreement** 已签署（否则内购不生效）。
- [ ] **App Store Server Notifications V2**：Sandbox + Production 回调 URL 均填后端 `https://<你的域名>/apple/notifications`。
- [ ] **Apple Root CA 证书**：从 https://www.apple.com/certificateauthority/ 下载 Apple Root CA 证书（G2/G3 等 `.cer`），放到后端 `notiee-ping-stream/certs/`（供 `SignedDataVerifier`）。
- [ ] **appAppleId**：ASC 里 App 的数字 ID（Production 验签需要），记下备用。
- [ ] **In-App Purchase capability**：Xcode Notiee target 加（Task 2 覆盖）。

---

# Part A — iOS 客户端

## Task 1: CurrentEntitlement 持久化（总闸，TDD）

**Files:**
- Modify: `Notiee/Models/CuratedModelCatalog.swift:77-79`（`CurrentEntitlement`）
- Modify: `Notiee/Utils/UserDefaultsKeys.swift`（加键）
- Modify: `Notiee/Services/EntitlementStore.swift`（quota 变化时写档位）
- Test: `NotieeTests/CurrentEntitlementTests.swift`

- [ ] **Step 1: 加 UserDefaults 键**

在 `Notiee/Utils/UserDefaultsKeys.swift` 的 curated model 键附近加：

```swift
    /// 当前档位缓存（"free"/"pro"）。持久化，供任意线程同步读取以驱动 UI 门控。
    /// 真值在后端，仅 UI 用；由 EntitlementStore 写入。
    static let entitlementTier = "notiee.entitlementTier"
```

- [ ] **Step 2: 写失败的测试**

创建 `NotieeTests/CurrentEntitlementTests.swift`：

```swift
import XCTest
@testable import Notiee

final class CurrentEntitlementTests: XCTestCase {
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "entitlement-\(UUID().uuidString)"
        CurrentEntitlement.defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        CurrentEntitlement.defaults.removePersistentDomain(forName: suite)
        CurrentEntitlement.defaults = .standard
        suite = nil
        super.tearDown()
    }

    func testDefaultsToFree() {
        XCTAssertEqual(CurrentEntitlement.tier, .free)
    }

    func testPersistsPro() {
        CurrentEntitlement.tier = .pro
        XCTAssertEqual(CurrentEntitlement.tier, .pro)
        XCTAssertEqual(CurrentEntitlement.defaults.string(forKey: UDK.entitlementTier), "pro")
    }

    func testUnknownRawFallsBackToFree() {
        CurrentEntitlement.defaults.set("enterprise", forKey: UDK.entitlementTier)
        XCTAssertEqual(CurrentEntitlement.tier, .free)
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

`⌘U`。Expected: FAIL —— `CurrentEntitlement.defaults` 不存在 / `tier` 只读。

- [ ] **Step 4: 改 CurrentEntitlement 为持久化**

把 `Notiee/Models/CuratedModelCatalog.swift` 末尾的：

```swift
enum CurrentEntitlement {
    static var tier: ModelTier { .free }
}
```

替换为：

```swift
/// 当前档位。**门控总闸**：Phase 4 起由后端真值驱动（`EntitlementStore` 写入），
/// 持久化到 UserDefaults 以便跨启动即时、且可从非主线程同步读取。默认 `.free`。
/// 客户端档位仅解锁 UI；后端对每次 AI 调用二次校验，改这里骗不到额度。
enum CurrentEntitlement {
    /// 可注入（测试用）；生产恒为 `.standard`。
    static var defaults: UserDefaults = .standard

    static var tier: ModelTier {
        get { ModelTier(rawValue: defaults.string(forKey: UDK.entitlementTier) ?? "") ?? .free }
        set { defaults.set(newValue.rawValue, forKey: UDK.entitlementTier) }
    }
}
```

- [ ] **Step 5: EntitlementStore 在 quota 变化时写档位**

在 `Notiee/Services/EntitlementStore.swift`，把：

```swift
    @Published private(set) var quota: BackendQuota?
```

替换为（加 `didSet` 同步写档位缓存）：

```swift
    @Published private(set) var quota: BackendQuota? {
        didSet { CurrentEntitlement.tier = (quota?.isPro == true) ? .pro : .free }
    }
```

> 效果：`/me/quota` 或 `/ai/process` 捎带的 quota 一旦显示 `tier=pro`，门控总闸即翻到 `.pro`；登出/降级则回 `.free`。

- [ ] **Step 6: 运行测试确认通过**

`⌘U`（`CurrentEntitlementTests`）。Expected: PASS。

- [ ] **Step 7: 编译两个 target**

`Notiee` `⌘B` + `Notiee+` `⌘B` → 均 BUILD SUCCEEDED（`CuratedModelCatalog.swift` 只在 Notiee；Notiee+ 不受影响）。

- [ ] **Step 8: 提交**

```bash
git add Notiee/Models/CuratedModelCatalog.swift \
        Notiee/Utils/UserDefaultsKeys.swift \
        Notiee/Services/EntitlementStore.swift \
        NotieeTests/CurrentEntitlementTests.swift
git commit -m "feat(entitlement): persist CurrentEntitlement tier, driven by EntitlementStore (unlocks tier gating)"
```

---

## Task 2: In-App Purchase 能力 + StoreKit 本地测试配置

**Files:**
- Xcode: Notiee target → Signing & Capabilities
- Create: `Notiee/Notiee.storekit`（StoreKit Configuration 文件）

- [ ] **Step 1: 加 In-App Purchase capability**

Xcode → 选 `Notiee` target → Signing & Capabilities → `+ Capability` → **In-App Purchase**。（`Notiee+` **不加**。）

- [ ] **Step 2: 新建 StoreKit Configuration 文件**

Xcode → File → New → File → **StoreKit Configuration File** → 命名 `Notiee.storekit`（放 `Notiee/` 下，勾 Notiee target 无所谓，它只用于本地测试）。
在其中 `+` → **Auto-Renewable Subscription**：
- Reference Name: `Notiee Pro Monthly`
- Product ID: **`com.idbetterrun.notiee.pro.monthly`**
- Subscription Duration: 1 Month
- Price: 18（本地测试价，随意）
- Subscription Group: `Notiee Pro`

- [ ] **Step 3: 让 Run 使用该配置**

Xcode → Product → Scheme → Edit Scheme → Run → Options → **StoreKit Configuration** → 选 `Notiee.storekit`。（这样模拟器购买不走真实 App Store。）

- [ ] **Step 4: 提交**

```bash
git add Notiee.xcodeproj Notiee/Notiee.storekit
git commit -m "chore(iap): add In-App Purchase capability and StoreKit config for local testing"
```

> 说明：此步无自动化测试；产物在 Task 3/4 完成后手动验证购买 UI 流程。

---

## Task 3: StoreKitService（StoreKit 2 购买 / 恢复 / 交易更新）

**Files:**
- Create: `Notiee/Services/StoreKitService.swift`（只勾 Notiee target）

- [ ] **Step 1: 写服务**

创建 `Notiee/Services/StoreKitService.swift`（**只勾 Notiee target**）：

```swift
import Foundation
import StoreKit

/// StoreKit 2 订阅：加载商品、购买、恢复、监听交易更新。每笔已验证交易把签名后的
/// JWS 上报后端 `/subscription/verify`，由后端置档位；随后刷新 EntitlementStore。
/// 仅 Notiee（免费）target。
@MainActor
final class StoreKitService: ObservableObject {
    static let shared = StoreKitService()

    static let proMonthlyID = "com.idbetterrun.notiee.pro.monthly"

    enum PurchaseState: Equatable {
        case idle, loading, purchasing, success, failed(String)
    }

    @Published private(set) var proProduct: Product?
    @Published private(set) var purchaseState: PurchaseState = .idle

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = listenForTransactions()
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.proMonthlyID])
            proProduct = products.first
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func purchasePro() async {
        guard let product = proProduct else {
            await loadProducts()
            return
        }
        purchaseState = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                await report(verification)
                purchaseState = .success
            case .userCancelled, .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        purchaseState = .loading
        try? await AppStore.sync()
        await reportCurrentEntitlements()
        purchaseState = .idle
    }

    // MARK: - Private

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await verification in Transaction.updates {
                await self?.report(verification)
            }
        }
    }

    /// 遍历当前有效权益，逐一上报（恢复购买 / 启动补偿用）。
    private func reportCurrentEntitlements() async {
        for await verification in Transaction.currentEntitlements {
            await report(verification)
        }
        await EntitlementStore.shared.refresh()
    }

    /// 上报一笔交易：仅接受设备端验签通过的，把 JWS 交后端复验，然后 finish + 刷新档位。
    private func report(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        _ = try? await BackendAPIClient.shared.postJSON(
            path: "subscription/verify",
            body: ["signedTransaction": verification.jwsRepresentation])
        await transaction.finish()
        await EntitlementStore.shared.refresh()
    }
}
```

- [ ] **Step 2: 编译确认通过**

`Notiee` `⌘B` → BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add Notiee/Services/StoreKitService.swift
git commit -m "feat(iap): StoreKitService (purchase/restore/updates → backend verify → refresh entitlement)"
```

---

## Task 4: PaywallView（合规付费墙 + 统一 paywallSheet）

**Files:**
- Create: `Notiee/Features/Settings/PaywallView.swift`（只勾 Notiee target）

- [ ] **Step 1: 写付费墙**

创建 `Notiee/Features/Settings/PaywallView.swift`（**只勾 Notiee target**）：

```swift
import SwiftUI
import StoreKit

/// Pro 订阅付费墙。审核 3.1.2：展示价格 / 周期 / 自动续订条款 + 恢复购买 + EULA/隐私链接。
/// 仅 Notiee（免费）target。
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var storeKit = StoreKitService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    priceAndPurchase
                    legalFooter
                }
                .padding()
            }
            .navigationTitle("Notiee Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("恢复购买") { Task { await storeKit.restore() } }
                }
            }
            .task { await storeKit.loadProducts() }
            .onChange(of: storeKit.purchaseState) { _, state in
                if state == .success { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill").font(.largeTitle).foregroundStyle(.yellow)
            Text("升级 Notiee Pro").font(.title2.bold())
            Text("解锁全部模型、Agent 智能体与更高额度")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            benefitRow("每月大幅提升处理额度")
            benefitRow("解锁全部文本 / 视觉模型")
            benefitRow("Spark Agent 智能体模式")
            benefitRow("对话不限轮数、记忆不限条数")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefitRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text)
            Spacer()
        }
    }

    private var priceAndPurchase: some View {
        VStack(spacing: 12) {
            if let product = storeKit.proProduct {
                Button {
                    Task { await storeKit.purchasePro() }
                } label: {
                    Text("\(product.displayPrice) / 月，订阅")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(storeKit.purchaseState == .purchasing)
            } else {
                ProgressView()
            }

            if case .failed(let msg) = storeKit.purchaseState {
                Text(msg).font(.caption).foregroundStyle(.red)
            }

            Text("订阅按月自动续订。除非在当前订阅周期结束前至少 24 小时关闭自动续订，否则将自动扣费续订。购买后可在 App Store 账户设置中管理或取消订阅。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var legalFooter: some View {
        HStack(spacing: 16) {
            legalLink(base: "UserAgreement", title: "用户协议 (EULA)")
            legalLink(base: "PrivacyPolicy", title: "隐私政策")
        }
        .font(.caption)
    }

    @ViewBuilder
    private func legalLink(base: String, title: String) -> some View {
        if let url = LegalDocument.bundleURL(base: base) {
            NavigationLink(title) {
                LegalHTMLView(url: url)
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        } else {
            Text(title).foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// 统一付费墙 sheet，替代各处占位 alert。仅 Notiee target。
    func paywallSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { PaywallView() }
    }
}
```

- [ ] **Step 2: 编译确认通过**

`Notiee` `⌘B` → BUILD SUCCEEDED。

- [ ] **Step 3: 手动核对（可选）**

模拟器（已选 `Notiee.storekit`）打开 PaywallView：显示 `¥18.00 / 月，订阅` 按钮、自动续订条款、EULA/隐私链接、恢复购买；点购买走本地 StoreKit 弹窗。

- [ ] **Step 4: 提交**

```bash
git add Notiee/Features/Settings/PaywallView.swift
git commit -m "feat(iap): PaywallView with 3.1.2-compliant copy, restore, legal links; paywallSheet modifier"
```

---

## Task 5: 三处付费墙触发点接上 PaywallView

**Files:**
- Modify: `Notiee/Features/Settings/QuotaCard.swift:31-36`
- Modify: `Notiee/Features/Settings/ModelPickerView.swift:24-28`
- Modify: `Notiee/Features/Spark/SparkView.swift:179-185`

- [ ] **Step 1: QuotaCard —— alert 换 paywallSheet**

把：

```swift
        .alert("升级 Pro 会员", isPresented: $showProUpsell) {
            Button("知道了", role: .cancel) {}
            // TODO(Phase 4): present PaywallView
        } message: {
            Text("升级 Pro 即可大幅提升每月额度，并解锁全部模型。")
        }
```

替换为：

```swift
        .paywallSheet(isPresented: $showProUpsell)
```

- [ ] **Step 2: ModelPickerView —— alert 换 paywallSheet**

把：

```swift
        .alert("Pro 专属模型", isPresented: $showProAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("该模型为 Pro 会员专属，升级后即可使用。")
        }
```

替换为：

```swift
        .paywallSheet(isPresented: $showProAlert)
```

- [ ] **Step 3: SparkView —— alert 换 paywallSheet（须 `#if !NOTIEE_PLUS`）**

把（附着在 `SparkAgentChip` 上的整段 alert）：

```swift
                .alert("升级 Pro 会员", isPresented: $showProUpsell) {
                    Button("知道了", role: .cancel) {}
                    // TODO(Phase 4): 改为 present PaywallView
                } message: {
                    Text("升级 Pro 即可解锁 Agent 智能体、更强模型与更长对话。")
                }
```

替换为：

```swift
                #if !NOTIEE_PLUS
                .paywallSheet(isPresented: $showProUpsell)
                #endif
```

> `PaywallView` 仅存在于 Notiee target，`SparkView` 是共享文件，故必须 `#if !NOTIEE_PLUS`。Notiee+ 里 `showProUpsell` 恒 false，无 sheet 也无妨。

- [ ] **Step 4: 编译两个 target（关键）**

1. `Notiee` `⌘B` → BUILD SUCCEEDED（三处点「升级 Pro」/锁定模型/Agent 锁 → 弹 PaywallView）。
2. `Notiee+` `⌘B` → BUILD SUCCEEDED（`SparkView` 不引用 PaywallView；QuotaCard/ModelPicker 不参与 Notiee+ 编译）。

- [ ] **Step 5: 手动核对端到端（客户端侧，StoreKit 本地）**

免费版：设置 → 模型选择 → 点带锁 Pro 模型 → 弹 PaywallView；「我」→ 额度卡片「升级 Pro」→ PaywallView；Spark → Agent 芯片（锁）→ PaywallView。本地 StoreKit 购买成功后 sheet 关闭（真正解锁需后端，见 Part B）。

- [ ] **Step 6: 提交**

```bash
git add Notiee/Features/Settings/QuotaCard.swift \
        Notiee/Features/Settings/ModelPickerView.swift \
        Notiee/Features/Spark/SparkView.swift
git commit -m "feat(iap): route all Pro upsell triggers to PaywallView"
```

---

# Part B — 后端（notiee-ping-stream）

> 需前置清单里的 Apple Root CA 证书（`certs/`）+ env（`APPLE_ENV`/`APPLE_BUNDLE_ID`/`APPLE_APP_APPLE_ID`）。本部分在后端目录内改，注意 `notiee-ping-stream/` 已 gitignore，用本地 zip 重新部署 SCF。

## Task 6: 装库 + 订阅映射表

**Files:**
- Modify: `notiee-ping-stream/package.json`（依赖）
- Modify: `notiee-ping-stream/schema.sql`
- Modify: `notiee-ping-stream/index.js`（store 加 subscription 读写）

- [ ] **Step 1: 装 App Store Server Library**

```bash
cd notiee-ping-stream && npm install @apple/app-store-server-library
```

- [ ] **Step 2: 建订阅映射表**

在 `notiee-ping-stream/schema.sql` 末尾追加：

```sql
-- 原始交易 → 用户 映射（App Store 通知按 original_transaction_id 回查用户）
CREATE TABLE IF NOT EXISTS subscriptions (
  original_transaction_id VARCHAR(64) NOT NULL PRIMARY KEY,
  user_id                 VARCHAR(64) NOT NULL,
  expires_at              DATETIME    NULL,
  updated_at              DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_sub_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

在 MySQL 控制台执行这段（建表）。

- [ ] **Step 3: store 两实现加 subscription 读写**

在 `memoryStore` 对象里加（`setTier` 之后）：

```swift
```
（下面是 JS，非 Swift）

```javascript
  subscriptions: new Map(), // otid -> { user_id, expires_at }
  async upsertSubscription(otid, userId, expiresMs) {
    this.subscriptions.set(otid, { user_id: userId, expires_at: expiresMs ? new Date(expiresMs) : null });
  },
  async getSubscription(otid) {
    return this.subscriptions.get(otid) || null;
  },
```

在 `mysqlStore` 对象里加（`setTier` 之后）：

```javascript
  async upsertSubscription(otid, userId, expiresMs) {
    await getPool().query(
      'INSERT INTO subscriptions (original_transaction_id, user_id, expires_at) VALUES (?, ?, ?) ' +
      'ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), expires_at = VALUES(expires_at)',
      [otid, userId, expiresMs ? new Date(expiresMs) : null]);
  },
  async getSubscription(otid) {
    const [rows] = await getPool().query(
      'SELECT user_id, expires_at FROM subscriptions WHERE original_transaction_id = ?', [otid]);
    return rows.length ? rows[0] : null;
  },
```

- [ ] **Step 4: 语法自检**

```bash
cd notiee-ping-stream && node --check index.js && echo OK
```
Expected: `OK`。

- [ ] **Step 5: 提交（iOS 仓库不含后端，此步在后端目录本地记录即可，可跳过 git）**

> `notiee-ping-stream/` 已 gitignore；如你对后端单独做了版本管理，在那边提交。

---

## Task 7: /subscription/verify 做实

**Files:**
- Modify: `notiee-ping-stream/index.js`（顶部加 verifier 工具 + 常量；替换 :443 stub）

- [ ] **Step 1: 顶部加 verifier 工具与常量**

在 index.js 顶部 `require` 区加：

```javascript
const fs = require('fs');
const { SignedDataVerifier, Environment } = require('@apple/app-store-server-library');

const PRO_PRODUCT_ID = 'com.idbetterrun.notiee.pro.monthly';

let _verifier = null;
function appleVerifier() {
  if (_verifier) return _verifier;
  const dir = __dirname + '/certs';
  const roots = fs.existsSync(dir)
    ? fs.readdirSync(dir).filter(f => f.endsWith('.cer')).map(f => fs.readFileSync(dir + '/' + f))
    : [];
  const env = process.env.APPLE_ENV === 'production' ? Environment.PRODUCTION : Environment.SANDBOX;
  _verifier = new SignedDataVerifier(
    roots,
    false, // enableOnlineChecks：关掉 OCSP，SCF 内更稳
    env,
    process.env.APPLE_BUNDLE_ID || 'com.idbetterrun.notiee',
    process.env.APPLE_APP_APPLE_ID ? Number(process.env.APPLE_APP_APPLE_ID) : undefined
  );
  return _verifier;
}

// 给定解码后的交易，落库并置档位。
async function applyTransaction(userId, tx) {
  const expiresMs = tx.expiresDate || 0;
  const active = expiresMs > Date.now();
  await store.upsertSubscription(tx.originalTransactionId, userId, expiresMs);
  await store.setTier(userId, active ? 'pro' : 'free', active ? new Date(expiresMs) : null);
  return active;
}
```

- [ ] **Step 2: 替换 /subscription/verify stub**

把（index.js:443 附近）：

```javascript
app.post('/subscription/verify', verifyToken, async (req, res) => {
```
整段（到该 handler 结束的 `});`）替换为：

```javascript
app.post('/subscription/verify', verifyToken, async (req, res) => {
  const { signedTransaction } = req.body || {};
  if (!signedTransaction) {
    return res.status(400).json({ error: { code: 'BAD_REQUEST', message: '缺少 signedTransaction' } });
  }
  try {
    const tx = await appleVerifier().verifyAndDecodeTransaction(signedTransaction);
    if (tx.productId !== PRO_PRODUCT_ID) {
      return res.status(400).json({ error: { code: 'BAD_REQUEST', message: '非 Pro 订阅商品' } });
    }
    await applyTransaction(req.userId, tx);
    const quota = await quotaFor(req.userId);
    res.json({ ok: true, quota });
  } catch (e) {
    res.status(400).json({ error: { code: 'APPLE_VERIFY_FAILED', message: String(e.message || e) } });
  }
});
```

- [ ] **Step 3: 语法自检**

```bash
cd notiee-ping-stream && node --check index.js && echo OK
```
Expected: `OK`。

- [ ] **Step 4: （部署后）沙盒联调**

配好 `certs/` + env（`APPLE_ENV=sandbox`、`APPLE_BUNDLE_ID`、`APPLE_APP_APPLE_ID`），重新打 zip 部署 SCF。真机用沙盒账号购买 → 客户端上报 → `/subscription/verify` 应返回 `{ok:true, quota:{tier:"pro",...}}`；DMC 查 `SELECT tier FROM users WHERE id=...` 应为 `pro`。

---

## Task 8: /apple/notifications 做实

**Files:**
- Modify: `notiee-ping-stream/index.js`（替换 :450 stub）

- [ ] **Step 1: 替换 /apple/notifications stub**

把（index.js:450 附近）：

```javascript
app.post('/apple/notifications', async (req, res) => {
```
整段替换为：

```javascript
app.post('/apple/notifications', async (req, res) => {
  const { signedPayload } = req.body || {};
  if (!signedPayload) return res.status(400).end();
  try {
    const notification = await appleVerifier().verifyAndDecodeNotification(signedPayload);
    const signedTx = notification.data && notification.data.signedTransactionInfo;
    if (signedTx) {
      const tx = await appleVerifier().verifyAndDecodeTransaction(signedTx);
      const sub = await store.getSubscription(tx.originalTransactionId);
      if (sub) {
        const revoked = ['EXPIRED', 'REFUND', 'REVOKE'].includes(notification.notificationType);
        if (revoked) {
          await store.setTier(sub.user_id, 'free', null);
          await store.upsertSubscription(tx.originalTransactionId, sub.user_id, tx.expiresDate || 0);
        } else {
          await applyTransaction(sub.user_id, tx);
        }
      }
    }
    res.status(200).end();
  } catch (e) {
    console.error('[apple/notifications]', e);
    res.status(200).end(); // 始终 200，避免 Apple 重试风暴；错误进日志
  }
});
```

- [ ] **Step 2: 语法自检**

```bash
cd notiee-ping-stream && node --check index.js && echo OK
```
Expected: `OK`。

- [ ] **Step 3: （部署后）验证续订/退款**

在 ASC 沙盒触发续订/退款，或用 App Store Server Notifications 测试工具，观察后端日志与 `users.tier` 随 `DID_RENEW`/`EXPIRED` 变化。

---

## Self-Review（作者已核对）

**Spec 覆盖（对照原 §4 Phase 4）：** `StoreKitService`（Task 3）✅；`PaywallView` 含 3.1.2 文案/EULA/隐私/恢复购买（Task 4）✅；三处触发点挂付费墙（Task 5）✅；StoreKit Configuration 本地测试（Task 2）✅；ASC 订阅产品配置（前置清单）✅；`EntitlementStore` 宽限期/过期 —— 由后端在通知里驱动（`applyTransaction` 按 `expiresDate` 判活；`EXPIRED/REFUND/REVOKE` 置 free），客户端 `tier` 保持二元、无需中间态字段。**总闸** `CurrentEntitlement` 持久化（Task 1）是让 Phase 2/2.5/3 门控真正响应 Pro 的关键，原清单未显式列出、此处补上。

**占位符扫描：** 无 TBD/空实现。Task 6 Step 3 有一个空的 ```swift 代码围栏标注紧接 JS——那是提示「下面是 JS 不是 Swift」的刻意注释，非占位。

**类型一致性：** 客户端 `StoreKitService.{proMonthlyID, proProduct, purchaseState, loadProducts(), purchasePro(), restore()}`（Task 3）与 `PaywallView`（Task 4）使用一致；`PurchaseState` Equatable 支撑 `onChange`/`== .purchasing`。`paywallSheet(isPresented:)`（Task 4）三处调用签名一致（Task 5）。`CurrentEntitlement.{defaults, tier}`（Task 1）与测试一致。后端 `appleVerifier()`/`applyTransaction()`/`PRO_PRODUCT_ID`/`store.upsertSubscription`/`store.getSubscription`（Task 6/7）跨 Task 7/8 一致。

**双 target 编译不变式：** Task 1 Step 7、Task 5 Step 4 各有「两个 target 都 `⌘B`」。`PaywallView`/`StoreKitService` 为 Notiee-only；`SparkView` 内唯一的 Notiee-only 引用（`paywallSheet`）已 `#if !NOTIEE_PLUS` 包裹。

**安全前提：** 客户端 `CurrentEntitlement`/StoreKit 校验仅解锁 UI；后端每次 AI 调用按 `users.tier` 二次校验，且订阅真值由 Apple 签名验签得出，改客户端本地值骗不到额度。

**跨端依赖：** Part A 的 `/subscription/verify` 上报在 Part B 未部署前会收到 501/400（`try?` 吞掉），客户端购买 UI 可独立用 StoreKit 配置测；端到端 Pro 解锁需 Part B 部署 + 前置清单（证书/ASC 产品/沙盒账号）。
```
