# Notiee: Multi-language Summaries, Security/Encryption, Custom-Model Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add (1) a Lab toggle that makes photo-note OCR/summary output follow the source language, (2) an app-level passcode + Face ID/Touch ID lock plus real AES-GCM encryption of individual captures managed from a new Security page, and (3) fix custom AI models never showing in the text/vision model pickers.

**Architecture:** Pure SwiftUI + MVVM app. Records persist as JSON (`records.json`) via `JSONNoteRecordStore`; images are JPEGs under `Documents/CapturedImages/`. Secrets live in Keychain via the existing `KeychainSecretStore`. Feature 1 appends an output-language directive to prompts built in `AIPromptProvider`. Feature 2 introduces `CryptoService` (CryptoKit AES-GCM, key in Keychain), `SecureRecordCodec` (encrypt/decrypt a single record's text + todos + image files), and `AppLockManager` (LocalAuthentication + passcode) gating the root view via `scenePhase`. Feature 3 lists `viewModel.customModels` in the existing `AIConfigurationView` picker and calls the already-present `SettingsViewModel.applyCustomModel`.

**Tech Stack:** Swift 5, SwiftUI, CryptoKit, LocalAuthentication, XCTest (`@testable import Notiee`), Xcode targets `Notiee` and `Notiee+` (shared source; `NOTIEE_PLUS` compilation condition — no `#if` branches needed).

**Conventions to follow:**
- Chinese UI strings, matching existing tone (see `LabFeaturesView.swift`, `SettingsMainView.swift`).
- Models use defensive `init(from:)` with `decodeIfPresent ?? default` (see `NoteRecord.swift`, `NoteTodo.swift`).
- Tests are `@MainActor final class ...: XCTestCase` in `NotieeTests/`.
- Run tests with: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/<ClassName>` (pick any installed simulator; `xcrun simctl list devices available` to find one).
- Commit after each task.

---

## File Structure

**Create:**
- `Notiee/Services/CryptoService.swift` — AES-GCM encrypt/decrypt + Keychain DEK + passcode hash/verify.
- `Notiee/Services/SecureRecordCodec.swift` — encrypt/decrypt one `NoteRecord` (text fields, todos, image files) end to end.
- `Notiee/Services/AppLockManager.swift` — `ObservableObject` singleton: enable/lock state, biometric + passcode auth, scenePhase re-lock.
- `Notiee/Features/Settings/AppLockView.swift` — full-screen lock overlay (biometric button + 6-digit passcode pad).
- `Notiee/Features/Settings/SecuritySettingsView.swift` — Security settings page.
- `NotieeTests/AIPromptOutputLanguageTests.swift`, `NotieeTests/CryptoServiceTests.swift`, `NotieeTests/NoteRecordEncryptedDecodingTests.swift`, `NotieeTests/SecureRecordCodecTests.swift`, `NotieeTests/CustomModelSelectionTests.swift`.

**Modify:**
- `Notiee/Utils/UserDefaultsKeys.swift` — new keys.
- `Notiee/Services/AIPromptProvider.swift` — output-language directive.
- `Notiee/Features/Settings/LabFeaturesView.swift` — output-language picker.
- `Notiee/Models/NoteRecord.swift` — `isEncrypted` field.
- `Notiee/Features/Settings/AIConfigurationView.swift` — list custom models in picker.
- `Notiee/Features/Settings/SettingsViewModel.swift` — expose custom-model selection binding helper.
- `Notiee/App/NotieeApp.swift` — mount lock overlay + scenePhase.
- `Notiee/Features/Settings/SettingsMainView.swift` — thread `store`, link to Security page.
- `Notiee/Features/Settings/MeView.swift` — update `SettingsMainView(...)` call site with `store`.
- `Notiee/Features/Records/RecordDetailView.swift` — 2-item toolbar + encrypt action + locked gating.
- `Notiee/Components/RecordCardView.swift`, `Notiee/Features/Records/RecordThumbnailView.swift` — locked placeholder.
- `Notiee/Services/TMNExportService.swift`, `Notiee/Services/ICloudSyncService.swift`, `Notiee/Services/Managers/RecordManager.swift` (search) — skip encrypted records.
- `Notiee copy-Info.plist`, `NotieeWidgetExtension copy-Info.plist`, `Notiee/Info.plist` — `NSFaceIDUsageDescription`.

---

# PHASE A — Feature 3: Custom models missing from text/vision pickers

**Root cause:** `AIConfigurationView.swift` builds its provider `Picker` from `AIProviderType.allCases` only; it never enumerates `viewModel.customModels`. `SettingsViewModel.applyCustomModel(_:for:)` exists but is never called.

### Task A1: Add a helper on SettingsViewModel + failing test

**Files:**
- Modify: `Notiee/Features/Settings/SettingsViewModel.swift`
- Test: `NotieeTests/CustomModelSelectionTests.swift`

- [ ] **Step 1: Write the failing test**

Create `NotieeTests/CustomModelSelectionTests.swift`:

```swift
import XCTest
@testable import Notiee

@MainActor
final class CustomModelSelectionTests: XCTestCase {
    private func makeVM() -> SettingsViewModel {
        // Uses the default live store; we only touch in-memory arrays here.
        let vm = SettingsViewModel()
        vm.customModels = []
        return vm
    }

    func testCustomModelsFilteredByKind() {
        let vm = makeVM()
        let textModel = CustomAIModel(name: "T", kind: .text, endpoint: "https://e/v1", protocolType: .openai, modelIdentifier: "m-t", apiKey: "k")
        let visionModel = CustomAIModel(name: "V", kind: .vision, endpoint: "https://e/v1", protocolType: .openai, modelIdentifier: "m-v", apiKey: "k")
        vm.customModels = [textModel, visionModel]

        XCTAssertEqual(vm.customModels(for: .text).map(\.id), [textModel.id])
        XCTAssertEqual(vm.customModels(for: .vision).map(\.id), [visionModel.id])
    }

    func testApplyCustomModelSetsCustomProvider() {
        let vm = makeVM()
        let model = CustomAIModel(name: "T", kind: .text, endpoint: "https://e/v1", protocolType: .openai, modelIdentifier: "m-t", apiKey: "k")
        vm.customModels = [model]

        vm.applyCustomModel(model, for: .text)

        XCTAssertEqual(vm.textConfiguration.providerType, .custom)
        XCTAssertEqual(vm.textConfiguration.customEndpoint, "https://e/v1")
        XCTAssertEqual(vm.textConfiguration.modelName, "m-t")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/CustomModelSelectionTests`
Expected: FAIL — `value of type 'SettingsViewModel' has no member 'customModels(for:)'`.

- [ ] **Step 3: Add the helper**

In `Notiee/Features/Settings/SettingsViewModel.swift`, after `applyCustomModel(_:for:)` (ends line ~179), add:

```swift
    /// Custom models that apply to a given model slot (text vs. vision).
    func customModels(for kind: AIModelKind) -> [CustomAIModel] {
        customModels.filter { $0.kind == kind }
    }

    /// The custom model currently backing a slot, if the slot uses a custom provider
    /// whose endpoint+model match one of the saved custom models.
    func activeCustomModel(for kind: AIModelKind) -> CustomAIModel? {
        let config = (kind == .text) ? textConfiguration : visionConfiguration
        guard config.providerType == .custom else { return nil }
        return customModels(for: kind).first {
            $0.endpoint == config.customEndpoint && $0.modelIdentifier == config.modelName
        }
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Notiee/Features/Settings/SettingsViewModel.swift NotieeTests/CustomModelSelectionTests.swift
git commit -m "feat(settings): add custom-model-by-kind helpers to SettingsViewModel"
```

### Task A2: Surface custom models in AIConfigurationView

**Files:**
- Modify: `Notiee/Features/Settings/AIConfigurationView.swift`

- [ ] **Step 1: Replace the provider Section and add a custom-models Section**

In `AIConfigurationView.body`, replace the existing `Section("服务商") { ... }` block (lines ~19-38) with the version below, and add a new `Section` immediately after it. The provider picker keeps built-in providers; a separate section lists custom models of this `kind` and applies them on selection.

Replace lines ~19-38 (`Section("服务商") { Picker(...) .onChange(...) }`) with:

```swift
            Section("服务商") {
                Picker("选择供应商", selection: configuration.providerType) {
                    if configuration.wrappedValue.providerType == .custom {
                        Text("自定义配置").tag(AIProviderType.custom)
                    }
                    ForEach(AIProviderType.allCases.filter { supports(provider: $0, for: kind) && $0 != .custom }) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: configuration.wrappedValue.providerType) { _, _ in
                    let currentProvider = configuration.wrappedValue.providerType
                    if currentProvider != .custom {
                        if let firstModel = currentProvider.predefinedModels.first {
                            configuration.wrappedValue.modelName = firstModel
                        } else {
                            configuration.wrappedValue.modelName = ""
                        }
                    }
                }
            }

            let customs = viewModel.customModels(for: kind)
            if !customs.isEmpty {
                Section("我的自定义模型") {
                    ForEach(customs) { model in
                        Button {
                            viewModel.applyCustomModel(model, for: kind)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.name).foregroundColor(.primary)
                                    Text(model.modelIdentifier)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if viewModel.activeCustomModel(for: kind)?.id == model.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("在「高级设置 → 管理自定义模型」中新增或修改。选中后即刻生效。")
                }
            }
```

Leave the rest of the view (the `if configuration.wrappedValue.providerType != .custom { Section("模型设置") ... }` block and the orange custom-config banner) unchanged.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual verification**

Launch the app (`/run` skill or Xcode). Settings → 高级设置 → 管理自定义模型 → add a model with type `文本处理模型`. Go to AI 配置 → 文本处理模型: the model appears under "我的自定义模型"; tapping it shows a checkmark and the top banner switches to the orange "正在使用自定义大模型" note. Repeat with a `图像识别模型` under 图像识别模型.

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Settings/AIConfigurationView.swift
git commit -m "fix(settings): show custom models in text/vision pickers (Notiee+)"
```

---

# PHASE B — Feature 1: Multi-language OCR/summary output (Lab)

**Root cause:** `AIPromptProvider` prompts exist only for `zh-Hans/zh-Hant/en` and output language implicitly follows the app UI language, so English content is summarized in Chinese and Korean content fails. Fix: append an explicit output-language directive (default: auto-detect from the source content).

### Task B1: New UDK key

**Files:**
- Modify: `Notiee/Utils/UserDefaultsKeys.swift`

- [ ] **Step 1: Add the key**

Next to the other `lab*` keys (around lines 91-94) add:

```swift
    static let labRecordOutputLanguage = "labRecordOutputLanguage"
```

- [ ] **Step 2: Commit** (build validated in B2)

```bash
git add Notiee/Utils/UserDefaultsKeys.swift
git commit -m "chore(udk): add labRecordOutputLanguage key"
```

### Task B2: Output-language directive in AIPromptProvider (TDD)

**Files:**
- Modify: `Notiee/Services/AIPromptProvider.swift`
- Test: `NotieeTests/AIPromptOutputLanguageTests.swift`

- [ ] **Step 1: Write the failing test**

Create `NotieeTests/AIPromptOutputLanguageTests.swift`:

```swift
import XCTest
@testable import Notiee

final class AIPromptOutputLanguageTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UDK.labRecordOutputLanguage)
        super.tearDown()
    }

    func testAutoDirectiveMentionsDetectingSourceLanguage() {
        UserDefaults.standard.set("auto", forKey: UDK.labRecordOutputLanguage)
        let d = AIPromptProvider.outputLanguageDirective()
        XCTAssertTrue(d.lowercased().contains("same language"))
        XCTAssertTrue(d.lowercased().contains("detect"))
    }

    func testExplicitDirectiveNamesKorean() {
        UserDefaults.standard.set("ko", forKey: UDK.labRecordOutputLanguage)
        let d = AIPromptProvider.outputLanguageDirective()
        XCTAssertTrue(d.contains("한국어"))
    }

    func testVisionPromptAppendsDirective() {
        UserDefaults.standard.set("ko", forKey: UDK.labRecordOutputLanguage)
        let p = AIPromptProvider.visionPrompt(fullVision: false, latex: false)
        XCTAssertTrue(p.system.contains("한국어"))
        XCTAssertTrue(p.user.contains("한국어"))
    }

    func testTextPromptAppendsDirective() {
        UserDefaults.standard.set("en", forKey: UDK.labRecordOutputLanguage)
        let p = AIPromptProvider.textPrompt(ocrText: "hello", enableSummary: true, enableDetailedContent: true, preset: .college)
        XCTAssertTrue(p.contains("English"))
    }
}
```

Note: `ScenePreset` cases are `.professional / .college / .highSchool / .creator` (no `.default`) — the test uses `.college`.

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/AIPromptOutputLanguageTests`
Expected: FAIL — `outputLanguageDirective` not found.

- [ ] **Step 3: Implement the directive**

In `Notiee/Services/AIPromptProvider.swift`, add to the `// MARK: - Public API` section:

```swift
    /// Reads the Lab output-language preference and returns an instruction appended
    /// to both vision and text prompts so the model produces output in the intended language.
    static func outputLanguageDirective(preference: String = UserDefaults.standard.string(forKey: UDK.labRecordOutputLanguage) ?? "auto") -> String {
        if preference == "auto" {
            return "\n\nOUTPUT LANGUAGE: Detect the dominant language of the source content (images/text) and produce ALL output fields (title, summary, detailedContent, keyPoints, definitions, todos) in that same language. Do not translate the content into any other language."
        }
        let name = outputLanguageDisplayName(preference)
        return "\n\nOUTPUT LANGUAGE: Produce ALL output fields (title, summary, detailedContent, keyPoints, definitions, todos) in \(name). If the source content is in another language, translate faithfully into \(name)."
    }

    /// Native display name for a language code, used inside the directive.
    static func outputLanguageDisplayName(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "简体中文 (Simplified Chinese)"
        case "zh-Hant": return "繁體中文 (Traditional Chinese)"
        case "en": return "English"
        case "ko": return "한국어 (Korean)"
        case "ja": return "日本語 (Japanese)"
        case "fr": return "Français (French)"
        case "de": return "Deutsch (German)"
        case "es": return "Español (Spanish)"
        default: return "简体中文 (Simplified Chinese)"
        }
    }
```

Then append the directive inside the two public builders. In `visionPrompt(...)` change the `return` to:

```swift
        let directive = outputLanguageDirective()
        return (user + directive, system + directive)
```

(Apply after the existing `if latex { ... }` block, replacing `return (user, system)`.)

In `textPrompt(...)`, wrap the switch result:

```swift
        let base: String
        switch lang {
        case "en": base = buildTextPromptEN(ocrText: ocrText, enableSummary: enableSummary, enableDetailedContent: enableDetailedContent, preset: preset, hasAdvanced: hasAdvanced)
        case "zh-Hant": base = buildTextPromptZHHant(ocrText: ocrText, enableSummary: enableSummary, enableDetailedContent: enableDetailedContent, preset: preset, hasAdvanced: hasAdvanced)
        default: base = buildTextPromptZHHans(ocrText: ocrText, enableSummary: enableSummary, enableDetailedContent: enableDetailedContent, preset: preset, hasAdvanced: hasAdvanced)
        }
        return base + outputLanguageDirective()
```

(Replace the existing `switch lang { case ...: return ... }` body.)

- [ ] **Step 4: Run to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Notiee/Services/AIPromptProvider.swift NotieeTests/AIPromptOutputLanguageTests.swift
git commit -m "feat(ai): append output-language directive to prompts (auto/explicit)"
```

### Task B3: Lab toggle UI

**Files:**
- Modify: `Notiee/Features/Settings/LabFeaturesView.swift`

- [ ] **Step 1: Add the AppStorage + Picker**

Add near the other `@AppStorage` declarations (after line 11):

```swift
    @AppStorage(UDK.labRecordOutputLanguage) private var recordOutputLanguage = "auto"
```

Add a new `Section` inside the `Form` (place it right after the `Section("语义检索")` block, before the iCloud section):

```swift
            Section("拍记输出语言") {
                Picker("总结与识别语言", selection: $recordOutputLanguage) {
                    Text("自动（跟随内容）").tag("auto")
                    Text("简体中文").tag("zh-Hans")
                    Text("繁體中文").tag("zh-Hant")
                    Text("English").tag("en")
                    Text("한국어").tag("ko")
                    Text("日本語").tag("ja")
                    Text("Français").tag("fr")
                    Text("Deutsch").tag("de")
                    Text("Español").tag("es")
                }
            } footer: {
                Text("控制拍记的标题、摘要、详细内容用哪种语言呈现。「自动」会识别图片/文字的主要语言并用同种语言总结（例如拍英文出英文、拍韩文出韩文）；也可固定为某一种语言强制翻译。只影响新的 AI 处理，已有记录不变。")
            }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual verification**

Settings → 实验室 → 拍记输出语言 = 自动. Capture (or import) an English document; confirm title/summary come back in English. Set to 한국어 and reprocess Korean content; confirm Korean output.

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Settings/LabFeaturesView.swift
git commit -m "feat(lab): add record output-language picker"
```

---

# PHASE C — Feature 2: Security (App lock + per-record encryption)

### Task C1: UDK keys + NoteRecord.isEncrypted (TDD decode)

**Files:**
- Modify: `Notiee/Utils/UserDefaultsKeys.swift`, `Notiee/Models/NoteRecord.swift`
- Test: `NotieeTests/NoteRecordEncryptedDecodingTests.swift`

- [ ] **Step 1: Add UDK keys**

Add a new group in `UserDefaultsKeys.swift`:

```swift
    // MARK: - Security
    static let securityAppLockEnabled = "notiee.security.appLockEnabled"
    static let securityBiometricEnabled = "notiee.security.biometricEnabled"
    static let securityAutoLockGraceSeconds = "notiee.security.autoLockGraceSeconds"
```

- [ ] **Step 2: Write failing decode test**

Create `NotieeTests/NoteRecordEncryptedDecodingTests.swift`. To avoid guessing enum raw values, the legacy test encodes a real record, strips the `isEncrypted` key from the JSON, and re-decodes:

```swift
import XCTest
@testable import Notiee

final class NoteRecordEncryptedDecodingTests: XCTestCase {
    func testDecodesLegacyRecordWithoutIsEncryptedAsFalse() throws {
        let record = NoteRecord(localImagePaths: [], title: "t")
        let data = try JSONEncoder().encode(record)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict.removeValue(forKey: "isEncrypted") // simulate old schema
        let legacy = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(NoteRecord.self, from: legacy)
        XCTAssertFalse(decoded.isEncrypted)
    }

    func testRoundTripEncryptedFlag() throws {
        var r = NoteRecord(localImagePaths: [], title: "x")
        r.isEncrypted = true
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(NoteRecord.self, from: data)
        XCTAssertTrue(decoded.isEncrypted)
    }
}
```

Note: `NoteRecord`'s initializer requires `localImagePaths:` (no default); `title:` defaults to `"待处理记录"`. All other params have defaults.

- [ ] **Step 3: Run to verify it fails**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/NoteRecordEncryptedDecodingTests`
Expected: FAIL — no member `isEncrypted`.

- [ ] **Step 4: Add the field**

In `Notiee/Models/NoteRecord.swift`:
1. Add stored property near `var source: RecordSource` (line ~32): `var isEncrypted: Bool`.
2. In the memberwise `init`, add parameter `isEncrypted: Bool = false` and `self.isEncrypted = isEncrypted`.
3. In `CodingKeys` (line ~82) add `isEncrypted` to the case list.
4. In `init(from:)` (near line 106) add: `isEncrypted = try c.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false`.

- [ ] **Step 5: Run to verify it passes**

Run: same as Step 3. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Notiee/Utils/UserDefaultsKeys.swift Notiee/Models/NoteRecord.swift NotieeTests/NoteRecordEncryptedDecodingTests.swift
git commit -m "feat(model): add NoteRecord.isEncrypted + security UDK keys"
```

### Task C2: CryptoService (TDD)

**Files:**
- Create: `Notiee/Services/CryptoService.swift`
- Test: `NotieeTests/CryptoServiceTests.swift`

- [ ] **Step 1: Write failing tests**

Create `NotieeTests/CryptoServiceTests.swift`:

```swift
import XCTest
import CryptoKit
@testable import Notiee

final class CryptoServiceTests: XCTestCase {
    private var svc: CryptoService!

    override func setUp() {
        super.setUp()
        // In-memory key so tests don't touch the real Keychain.
        svc = CryptoService(key: SymmetricKey(size: .bits256))
    }

    func testDataRoundTrip() throws {
        let plain = Data("한국어 secret 机密".utf8)
        let cipher = try svc.encrypt(plain)
        XCTAssertNotEqual(cipher, plain)
        XCTAssertEqual(try svc.decrypt(cipher), plain)
    }

    func testStringRoundTrip() throws {
        let s = "summary text 摘要"
        XCTAssertEqual(try svc.decryptString(svc.encryptString(s)), s)
    }

    func testPasscodeHashVerifies() {
        let salt = CryptoService.makeSalt()
        let hash = CryptoService.hashPasscode("123456", salt: salt)
        XCTAssertTrue(CryptoService.verifyPasscode("123456", salt: salt, expectedHash: hash))
        XCTAssertFalse(CryptoService.verifyPasscode("000000", salt: salt, expectedHash: hash))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/CryptoServiceTests`
Expected: FAIL — `CryptoService` not found.

- [ ] **Step 3: Implement CryptoService**

Create `Notiee/Services/CryptoService.swift`:

```swift
import Foundation
import CryptoKit

/// AES-GCM encryption for per-record content, plus passcode hashing.
///
/// Threat model: record text and images are stored as ciphertext on disk. The data
/// key (DEK) lives in the Keychain (`WhenUnlockedThisDeviceOnly`, not synced), so at
/// rest the content is unreadable without the device being unlocked. The app-lock
/// passcode / biometric gates the UI that reveals decrypted content. A future
/// enhancement could bind the DEK to a biometric Keychain ACL.
struct CryptoService {
    enum CryptoError: LocalizedError {
        case keyUnavailable
        case badCiphertext
        var errorDescription: String? {
            switch self {
            case .keyUnavailable: return "加密密钥不可用。"
            case .badCiphertext: return "密文无法解析。"
            }
        }
    }

    private let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }

    // MARK: - Symmetric crypto

    func encrypt(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw CryptoError.badCiphertext }
        return combined
    }

    func decrypt(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    func encryptString(_ s: String) -> String {
        (try? encrypt(Data(s.utf8)))?.base64EncodedString() ?? ""
    }

    func decryptString(_ base64: String) throws -> String {
        guard let data = Data(base64Encoded: base64) else { throw CryptoError.badCiphertext }
        return String(decoding: try decrypt(data), as: UTF8.self)
    }

    // MARK: - Keychain-backed DEK

    private static let dekKeychainKey = "notiee.security.dek"

    /// Returns the shared record-encryption service, creating & persisting a DEK on first use.
    static func shared(secretStore: SecretPersisting = KeychainSecretStore()) -> CryptoService {
        if let b64 = secretStore.string(forKey: dekKeychainKey),
           let raw = Data(base64Encoded: b64) {
            return CryptoService(key: SymmetricKey(data: raw))
        }
        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        try? secretStore.setString(raw.base64EncodedString(), forKey: dekKeychainKey)
        return CryptoService(key: key)
    }

    // MARK: - Passcode hashing

    static func makeSalt() -> String {
        SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }.base64EncodedString()
    }

    static func hashPasscode(_ passcode: String, salt: String) -> String {
        let input = Data((salt + ":" + passcode).utf8)
        return Data(SHA256.hash(data: input)).base64EncodedString()
    }

    static func verifyPasscode(_ passcode: String, salt: String, expectedHash: String) -> Bool {
        hashPasscode(passcode, salt: salt) == expectedHash
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Notiee/Services/CryptoService.swift NotieeTests/CryptoServiceTests.swift
git commit -m "feat(security): add CryptoService (AES-GCM + Keychain DEK + passcode hash)"
```

### Task C3: SecureRecordCodec — encrypt/decrypt a record (TDD)

Encrypts a record's sensitive text + its todos + its image files, blanking plaintext from the persisted model. Decryption reverses it. Operations are ordered write-then-delete so a mid-way failure never loses plaintext.

**Files:**
- Create: `Notiee/Services/SecureRecordCodec.swift`
- Test: `NotieeTests/SecureRecordCodecTests.swift`

- [ ] **Step 1: Write failing test**

Create `NotieeTests/SecureRecordCodecTests.swift`:

```swift
import XCTest
import CryptoKit
@testable import Notiee

@MainActor
final class SecureRecordCodecTests: XCTestCase {
    func testEncryptThenDecryptRestoresText() throws {
        let crypto = CryptoService(key: SymmetricKey(size: .bits256))
        let codec = SecureRecordCodec(crypto: crypto)

        var record = NoteRecord(localImagePaths: [], title: "My Title")
        record.ocrText = "raw ocr"
        record.summary = "the summary"
        record.detailedContent = "detail body"
        record.keyPoints = ["a", "b"]

        let todos = [NoteTodo(recordID: record.id, content: "buy milk")]

        let (encRecord, blob) = try codec.encrypt(record: record, todos: todos)
        XCTAssertTrue(encRecord.isEncrypted)
        XCTAssertEqual(encRecord.ocrText, "")
        XCTAssertEqual(encRecord.summary, "")
        XCTAssertEqual(encRecord.keyPoints, [])
        XCTAssertNotEqual(encRecord.title, "My Title") // placeholder

        let (decRecord, decTodos) = try codec.decrypt(record: encRecord, blob: blob)
        XCTAssertFalse(decRecord.isEncrypted)
        XCTAssertEqual(decRecord.title, "My Title")
        XCTAssertEqual(decRecord.summary, "the summary")
        XCTAssertEqual(decRecord.keyPoints, ["a", "b"])
        XCTAssertEqual(decTodos.map(\.content), ["buy milk"])
    }
}
```

Note: this test exercises text only (no image files).

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests/SecureRecordCodecTests`
Expected: FAIL — `SecureRecordCodec` not found.

- [ ] **Step 3: Implement SecureRecordCodec**

Create `Notiee/Services/SecureRecordCodec.swift`:

```swift
import Foundation
import UIKit

/// Encrypts / decrypts a single NoteRecord's sensitive payload (text fields + todos)
/// and its image files. The encrypted blob (Data) holds the JSON of the sensitive
/// payload; callers persist it separately (see SecureRecordCodec.blobURL).
@MainActor
struct SecureRecordCodec {
    struct SensitivePayload: Codable {
        var title: String
        var ocrText: String
        var summary: String
        var detailedContent: String
        var keyPoints: [String]
        var definitions: [KeyDefinition]
        var todos: [NoteTodo]
    }

    static let lockedPlaceholderTitle = "🔒 已加密拍记"

    private let crypto: CryptoService
    private let fileManager = FileManager.default

    init(crypto: CryptoService) {
        self.crypto = crypto
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var encryptedDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("EncryptedRecords", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func blobURL(for recordID: UUID) -> URL {
        encryptedDirectory.appendingPathComponent("\(recordID.uuidString).enc")
    }

    // MARK: - Encrypt

    /// Returns the redacted record (to persist) and the ciphertext blob (to write to disk).
    func encrypt(record: NoteRecord, todos: [NoteTodo]) throws -> (record: NoteRecord, blob: Data) {
        let payload = SensitivePayload(
            title: record.title,
            ocrText: record.ocrText,
            summary: record.summary,
            detailedContent: record.detailedContent,
            keyPoints: record.keyPoints,
            definitions: record.definitions,
            todos: todos
        )
        let blob = try crypto.encrypt(try JSONEncoder().encode(payload))

        // Encrypt image files: write "<path>.enc" first, then delete the plaintext.
        var newPaths: [String] = []
        for path in record.localImagePaths {
            if path.hasPrefix("mock://") { newPaths.append(path); continue }
            let src = documentsDirectory.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: src) else { newPaths.append(path); continue }
            let encData = try crypto.encrypt(data)
            let encPath = path + ".enc"
            try encData.write(to: documentsDirectory.appendingPathComponent(encPath), options: [.atomic])
            try? fileManager.removeItem(at: src)
            newPaths.append(encPath)
        }

        var redacted = record
        redacted.title = Self.lockedPlaceholderTitle
        redacted.ocrText = ""
        redacted.summary = ""
        redacted.detailedContent = ""
        redacted.keyPoints = []
        redacted.definitions = []
        redacted.localImagePaths = newPaths
        redacted.isEncrypted = true
        return (redacted, blob)
    }

    // MARK: - Decrypt

    /// Returns the restored record and its todos. Also restores image files on disk.
    func decrypt(record: NoteRecord, blob: Data) throws -> (record: NoteRecord, todos: [NoteTodo]) {
        let payload = try JSONDecoder().decode(SensitivePayload.self, from: try crypto.decrypt(blob))

        var restoredPaths: [String] = []
        for path in record.localImagePaths {
            if path.hasPrefix("mock://") || !path.hasSuffix(".enc") { restoredPaths.append(path); continue }
            let encURL = documentsDirectory.appendingPathComponent(path)
            guard let encData = try? Data(contentsOf: encURL) else { restoredPaths.append(path); continue }
            let plainData = try crypto.decrypt(encData)
            let plainPath = String(path.dropLast(4)) // strip ".enc"
            try plainData.write(to: documentsDirectory.appendingPathComponent(plainPath), options: [.atomic])
            try? fileManager.removeItem(at: encURL)
            restoredPaths.append(plainPath)
        }

        var restored = record
        restored.title = payload.title
        restored.ocrText = payload.ocrText
        restored.summary = payload.summary
        restored.detailedContent = payload.detailedContent
        restored.keyPoints = payload.keyPoints
        restored.definitions = payload.definitions
        restored.localImagePaths = restoredPaths
        restored.isEncrypted = false
        return (restored, payload.todos)
    }

    /// In-memory decrypt for viewing (does NOT touch disk image files; used with decryptedImage()).
    func decryptForViewing(record: NoteRecord, blob: Data) throws -> (record: NoteRecord, todos: [NoteTodo]) {
        let payload = try JSONDecoder().decode(SensitivePayload.self, from: try crypto.decrypt(blob))
        var view = record
        view.title = payload.title
        view.ocrText = payload.ocrText
        view.summary = payload.summary
        view.detailedContent = payload.detailedContent
        view.keyPoints = payload.keyPoints
        view.definitions = payload.definitions
        return (view, payload.todos)
    }

    /// Loads and decrypts a single encrypted image (path ends in ".enc").
    func decryptedImage(atEncryptedPath path: String) -> UIImage? {
        let url = documentsDirectory.appendingPathComponent(path)
        guard let encData = try? Data(contentsOf: url),
              let plain = try? crypto.decrypt(encData) else { return nil }
        return UIImage(data: plain)
    }

    func writeBlob(_ blob: Data, for recordID: UUID) throws {
        try blob.write(to: blobURL(for: recordID), options: [.atomic])
    }

    func readBlob(for recordID: UUID) -> Data? {
        try? Data(contentsOf: blobURL(for: recordID))
    }

    func deleteBlob(for recordID: UUID) {
        try? fileManager.removeItem(at: blobURL(for: recordID))
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: same as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Notiee/Services/SecureRecordCodec.swift NotieeTests/SecureRecordCodecTests.swift
git commit -m "feat(security): add SecureRecordCodec (per-record encrypt/decrypt)"
```

### Task C4: Store-level encrypt/decrypt orchestration on NotieeStore

Wire the codec to the store so views can encrypt/decrypt a record and persistence + todos stay consistent.

**Files:**
- Modify: `Notiee/Services/NotieeStore.swift`

- [ ] **Step 1: Add methods**

In `NotieeStore` (after `updateRecordEvent`, around line 367), add:

```swift
    // MARK: - Encryption

    /// Encrypts a single record in place: writes the ciphertext blob, redacts the
    /// persisted record, and clears its todos from the todo store.
    func encryptRecord(id: UUID) {
        guard let record = records.first(where: { $0.id == id }), !record.isEncrypted else { return }
        let codec = SecureRecordCodec(crypto: CryptoService.shared())
        let recordTodos = todos(for: record)
        do {
            let (redacted, blob) = try codec.encrypt(record: record, todos: recordTodos)
            try codec.writeBlob(blob, for: id)
            replaceTodos(for: id, with: [])
            updateRecord(redacted)
        } catch {
            lastPersistenceError = "加密失败：\(error.localizedDescription)"
        }
    }

    /// Permanently decrypts a record: restores text, todos, and image files; removes the blob.
    func decryptRecord(id: UUID) {
        guard let record = records.first(where: { $0.id == id }), record.isEncrypted else { return }
        let codec = SecureRecordCodec(crypto: CryptoService.shared())
        guard let blob = codec.readBlob(for: id) else {
            lastPersistenceError = "找不到加密数据。"
            return
        }
        do {
            let (restored, restoredTodos) = try codec.decrypt(record: record, blob: blob)
            updateRecord(restored)
            replaceTodos(for: id, with: restoredTodos)
            codec.deleteBlob(for: id)
        } catch {
            lastPersistenceError = "解密失败：\(error.localizedDescription)"
        }
    }

    /// In-memory decrypt for viewing an encrypted record without persisting plaintext.
    func decryptedForViewing(_ record: NoteRecord) -> (record: NoteRecord, todos: [NoteTodo])? {
        guard record.isEncrypted else { return (record, todos(for: record)) }
        let codec = SecureRecordCodec(crypto: CryptoService.shared())
        guard let blob = codec.readBlob(for: record.id),
              let result = try? codec.decryptForViewing(record: record, blob: blob) else { return nil }
        return result
    }

    /// Decrypts all encrypted records (used when disabling the security feature).
    func decryptAllRecords() {
        for record in records where record.isEncrypted {
            decryptRecord(id: record.id)
        }
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Notiee/Services/NotieeStore.swift
git commit -m "feat(store): encrypt/decrypt record orchestration"
```

### Task C5: AppLockManager

**Files:**
- Create: `Notiee/Services/AppLockManager.swift`

- [ ] **Step 1: Implement**

Create `Notiee/Services/AppLockManager.swift`:

```swift
import Foundation
import LocalAuthentication
import Combine

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published var isLocked: Bool = false

    private let secretStore: SecretPersisting
    private var backgroundedAt: Date?

    private static let passcodeHashKey = "notiee.security.passcodeHash"
    private static let passcodeSaltKey = "notiee.security.passcodeSalt"

    init(secretStore: SecretPersisting = KeychainSecretStore()) {
        self.secretStore = secretStore
        // Lock on cold start if the feature is enabled.
        isLocked = isEnabled
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UDK.securityAppLockEnabled)
    }

    var biometricEnabled: Bool {
        UserDefaults.standard.bool(forKey: UDK.securityBiometricEnabled)
    }

    var hasPasscode: Bool {
        secretStore.string(forKey: Self.passcodeHashKey) != nil
    }

    private var graceSeconds: TimeInterval {
        let v = UserDefaults.standard.integer(forKey: UDK.securityAutoLockGraceSeconds)
        return v > 0 ? TimeInterval(v) : 0 // 0 = lock immediately on return
    }

    // MARK: - Passcode

    func setPasscode(_ passcode: String) {
        let salt = CryptoService.makeSalt()
        let hash = CryptoService.hashPasscode(passcode, salt: salt)
        try? secretStore.setString(salt, forKey: Self.passcodeSaltKey)
        try? secretStore.setString(hash, forKey: Self.passcodeHashKey)
    }

    func verifyPasscode(_ passcode: String) -> Bool {
        guard let salt = secretStore.string(forKey: Self.passcodeSaltKey),
              let hash = secretStore.string(forKey: Self.passcodeHashKey) else { return false }
        return CryptoService.verifyPasscode(passcode, salt: salt, expectedHash: hash)
    }

    func clearPasscode() {
        try? secretStore.removeString(forKey: Self.passcodeHashKey)
        try? secretStore.removeString(forKey: Self.passcodeSaltKey)
    }

    // MARK: - Enable / disable

    func enable(passcode: String, biometric: Bool) {
        setPasscode(passcode)
        UserDefaults.standard.set(true, forKey: UDK.securityAppLockEnabled)
        UserDefaults.standard.set(biometric, forKey: UDK.securityBiometricEnabled)
        isLocked = false
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: UDK.securityAppLockEnabled)
        UserDefaults.standard.set(false, forKey: UDK.securityBiometricEnabled)
        clearPasscode()
        isLocked = false
    }

    // MARK: - Locking lifecycle

    func appDidEnterBackground() {
        guard isEnabled else { return }
        backgroundedAt = Date()
    }

    func appWillEnterForeground() {
        guard isEnabled else { return }
        if let at = backgroundedAt, Date().timeIntervalSince(at) < graceSeconds {
            return
        }
        isLocked = true
    }

    func lockNow() {
        guard isEnabled else { return }
        isLocked = true
    }

    // MARK: - Biometric

    var biometryTypeName: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "生物识别"
        }
    }

    var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Authenticate with biometrics; on success clears the lock. Completion(false) lets the
    /// UI fall back to passcode entry.
    func authenticateWithBiometrics(reason: String = "解锁 Notiee") async -> Bool {
        let ctx = LAContext()
        guard biometricEnabled, ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return false
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if ok { isLocked = false }
            return ok
        } catch {
            return false
        }
    }

    func unlockWithPasscode(_ passcode: String) -> Bool {
        guard verifyPasscode(passcode) else { return false }
        isLocked = false
        return true
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Notiee/Services/AppLockManager.swift
git commit -m "feat(security): add AppLockManager (biometric + passcode + relock)"
```

### Task C6: AppLockView (lock overlay + passcode pad)

**Files:**
- Create: `Notiee/Features/Settings/AppLockView.swift`

- [ ] **Step 1: Implement**

Create `Notiee/Features/Settings/AppLockView.swift`:

```swift
import SwiftUI

/// Full-screen lock overlay. Verifies against AppLockManager and, on success,
/// AppLockManager sets isLocked = false, dismissing this overlay.
struct AppLockView: View {
    @ObservedObject var lock: AppLockManager
    @State private var entered = ""
    @State private var showError = false

    private let pinLength = 6

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.accentColor)
                Text("已锁定").font(.title2.bold())
                Text(showError ? "密码错误，请重试" : "输入密码解锁")
                    .font(.subheadline)
                    .foregroundColor(showError ? .red : .secondary)

                dots

                if lock.biometricEnabled && lock.biometryAvailable {
                    Button {
                        Task { _ = await lock.authenticateWithBiometrics() }
                    } label: {
                        Label("使用 \(lock.biometryTypeName)", systemImage: "faceid")
                    }
                }

                Spacer()
                keypad
                    .padding(.bottom, 24)
            }
            .padding()
        }
        .onAppear {
            if lock.biometricEnabled && lock.biometryAvailable {
                Task { _ = await lock.authenticateWithBiometrics() }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 16) {
            ForEach(0..<pinLength, id: \.self) { i in
                Circle()
                    .fill(i < entered.count ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 14, height: 14)
            }
        }
    }

    private var keypad: some View {
        let keys: [[String]] = [["1","2","3"],["4","5","6"],["7","8","9"],["","0","⌫"]]
        return VStack(spacing: 18) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 28) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 72, height: 72)
        } else {
            Button {
                handleKey(key)
            } label: {
                Text(key)
                    .font(.title.weight(.regular))
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color.secondary.opacity(0.12)))
            }
            .foregroundColor(.primary)
        }
    }

    private func handleKey(_ key: String) {
        showError = false
        if key == "⌫" {
            if !entered.isEmpty { entered.removeLast() }
            return
        }
        guard entered.count < pinLength else { return }
        entered.append(key)
        if entered.count == pinLength {
            if lock.unlockWithPasscode(entered) {
                entered = ""
            } else {
                showError = true
                entered = ""
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Notiee/Features/Settings/AppLockView.swift
git commit -m "feat(security): add AppLockView passcode/biometric overlay"
```

### Task C7: Mount the lock in NotieeApp + Face ID usage string

**Files:**
- Modify: `Notiee/App/NotieeApp.swift`, `Notiee copy-Info.plist`, `NotieeWidgetExtension copy-Info.plist`, `Notiee/Info.plist`

- [ ] **Step 1: Wire the overlay + scenePhase**

In `Notiee/App/NotieeApp.swift`:
1. Add to the `NotieeApp` struct properties: `@StateObject private var appLock = AppLockManager.shared` and `@Environment(\.scenePhase) private var scenePhase`.
2. Wrap the existing `Group { ... }` content in a `ZStack` overlay. Replace the `.preferredColorScheme/.tint/.environment` chain's host so the overlay sits on top. Concretely, change the `WindowGroup { Group { ... } .preferredColorScheme(...)... }` to:

```swift
        WindowGroup {
            ZStack {
                Group {
                    if !hasAgreedToPrivacy {
                        PrivacyAgreementView(hasAgreed: $hasAgreedToPrivacy)
                    } else if !hasSeenWelcome {
                        WelcomeView {
                            SystemPermissionManager.shared.requestAllPermissions {
                                hasSeenWelcome = true
                            }
                        }
                    } else if lastAppVersion != "" && lastAppVersion != currentAppVersion {
                        WhatsNewContainerView {
                            lastAppVersion = currentAppVersion
                        }
                    } else {
                        RootTabView()
                            .onAppear {
                                if lastAppVersion == "" {
                                    lastAppVersion = currentAppVersion
                                }
                            }
                    }
                }

                if appLock.isLocked {
                    AppLockView(lock: appLock)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .preferredColorScheme(colorScheme)
            .tint(appTint)
            .environment(\.sizeCategory, contentSizeCategory)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                appLock.appDidEnterBackground()
            case .active:
                appLock.appWillEnterForeground()
            default:
                break
            }
        }
```

Note: `.onChange(of:scenePhase)` attaches to the `WindowGroup` (a `Scene`), which is valid in SwiftUI. If the compiler rejects it on the Scene, move `.onChange` onto the `ZStack` instead.

- [ ] **Step 2: Add NSFaceIDUsageDescription to all three plists**

In each of `Notiee copy-Info.plist`, `NotieeWidgetExtension copy-Info.plist`, and `Notiee/Info.plist`, add inside the top-level `<dict>`:

```xml
	<key>NSFaceIDUsageDescription</key>
	<string>用于快速解锁 Notiee 及查看加密拍记。</string>
```

(The widget extension does not use Face ID, but adding the key is harmless and keeps parity; if the widget plist is minimal and you prefer, you may skip it — the app target plist `Notiee copy-Info.plist` is the required one.)

- [ ] **Step 3: Build**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Notiee/App/NotieeApp.swift "Notiee copy-Info.plist" "NotieeWidgetExtension copy-Info.plist" Notiee/Info.plist
git commit -m "feat(security): mount app-lock overlay + scenePhase relock + FaceID usage string"
```

### Task C8: SecuritySettingsView + link from SettingsMainView

**Files:**
- Create: `Notiee/Features/Settings/SecuritySettingsView.swift`
- Modify: `Notiee/Features/Settings/SettingsMainView.swift`, `Notiee/Features/Settings/MeView.swift`

- [ ] **Step 1: Implement SecuritySettingsView**

Create `Notiee/Features/Settings/SecuritySettingsView.swift`:

```swift
import SwiftUI

struct SecuritySettingsView: View {
    @ObservedObject var store: NotieeStore
    @StateObject private var lock = AppLockManager.shared

    @State private var showSetPasscode = false
    @State private var showDisableConfirm = false
    @State private var pendingPasscode = ""
    @State private var confirmPasscode = ""
    @State private var enableBiometric = true
    @State private var verifyInput = ""
    @State private var showVerifyForDisable = false
    @State private var errorText: String?

    private var encryptedRecords: [NoteRecord] {
        store.records.filter { $0.isEncrypted && !$0.isDeleted }
    }

    var body: some View {
        Form {
            Section {
                Toggle("打开 App 需要密码", isOn: Binding(
                    get: { lock.isEnabled },
                    set: { newValue in
                        if newValue {
                            showSetPasscode = true
                        } else {
                            showVerifyForDisable = true
                        }
                    }
                ))
            } footer: {
                Text("开启后每次启动或从后台返回都需要验证。")
            }

            if lock.isEnabled {
                Section {
                    Toggle("使用 \(lock.biometryTypeName) 快速解锁", isOn: Binding(
                        get: { lock.biometricEnabled },
                        set: { UserDefaults.standard.set($0, forKey: UDK.securityBiometricEnabled) }
                    ))
                    .disabled(!lock.biometryAvailable)
                } footer: {
                    Text(lock.biometryAvailable ? "解锁 App 与查看加密拍记时可用。" : "此设备不支持生物识别。")
                }

                Section("已加密的拍记") {
                    if encryptedRecords.isEmpty {
                        Text("暂无加密拍记。在记录详情页「更多 → 加密该条拍记」加密。")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(encryptedRecords) { record in
                            HStack {
                                Image(systemName: "lock.doc.fill").foregroundColor(.accentColor)
                                Text(record.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                Spacer()
                                Button("解除加密") {
                                    authenticate { store.decryptRecord(id: record.id) }
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                } footer: {
                    Text("关闭单条拍记的加密只能在此处操作。")
                }
            }

            if let errorText {
                Section { Text(errorText).foregroundColor(.red) }
            }
        }
        .navigationTitle("安全")
        .navigationBarTitleDisplayMode(.inline)
        // Set passcode flow
        .sheet(isPresented: $showSetPasscode) {
            SetPasscodeSheet(onCancel: { showSetPasscode = false }) { code in
                lock.enable(passcode: code, biometric: lock.biometryAvailable && enableBiometric)
                showSetPasscode = false
            }
        }
        // Verify to disable
        .alert("验证以关闭安全", isPresented: $showVerifyForDisable) {
            SecureField("6 位密码", text: $verifyInput)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) { verifyInput = "" }
            Button("确认关闭", role: .destructive) {
                if lock.verifyPasscode(verifyInput) {
                    verifyInput = ""
                    if !encryptedRecords.isEmpty {
                        showDisableConfirm = true
                    } else {
                        lock.disable()
                    }
                } else {
                    errorText = "密码错误。"
                    verifyInput = ""
                }
            }
        } message: {
            Text("关闭后所有已加密拍记将被解密恢复为明文。")
        }
        .alert("确认关闭安全功能？", isPresented: $showDisableConfirm) {
            Button("取消", role: .cancel) {}
            Button("解密全部并关闭", role: .destructive) {
                store.decryptAllRecords()
                lock.disable()
            }
        } message: {
            Text("将解密 \(encryptedRecords.count) 条已加密拍记。")
        }
    }

    /// Runs `action` after a fresh biometric/passcode check.
    private func authenticate(_ action: @escaping () -> Void) {
        Task {
            if await lock.authenticateWithBiometrics(reason: "解除拍记加密") {
                action()
            } else {
                // Fallback: require passcode via a simple prompt.
                await MainActor.run { showPasscodePromptForAction(action) }
            }
        }
    }

    // Minimal inline passcode prompt fallback for per-record decrypt.
    @State private var actionPasscode = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showActionPrompt = false

    private func showPasscodePromptForAction(_ action: @escaping () -> Void) {
        pendingAction = action
        showActionPrompt = true
    }
}

/// Two-field passcode creation sheet.
private struct SetPasscodeSheet: View {
    let onCancel: () -> Void
    let onDone: (String) -> Void
    @State private var a = ""
    @State private var b = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("设置 6 位密码") {
                    SecureField("输入密码", text: $a).keyboardType(.numberPad)
                    SecureField("再次输入", text: $b).keyboardType(.numberPad)
                }
                if let error { Text(error).foregroundColor(.red) }
            }
            .navigationTitle("设置密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消", action: onCancel) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        guard a.count == 6, a.allSatisfy(\.isNumber) else { error = "请输入 6 位数字。"; return }
                        guard a == b else { error = "两次输入不一致。"; return }
                        onDone(a)
                    }
                }
            }
        }
    }
}
```

Note: to keep the sheet simple the per-record passcode fallback (`showActionPrompt`) is scaffolded but the biometric path is primary. If biometrics are unavailable, add an `.alert("输入密码", isPresented: $showActionPrompt)` with a `SecureField` bound to `actionPasscode` that calls `pendingAction` when `lock.verifyPasscode(actionPasscode)` succeeds — mirror the disable alert above. Include this alert before shipping.

- [ ] **Step 2: Add the "已实现完整密码回退" alert**

Append this modifier to the `Form` (after the `.alert(... showDisableConfirm ...)`):

```swift
        .alert("输入密码", isPresented: $showActionPrompt) {
            SecureField("6 位密码", text: $actionPasscode).keyboardType(.numberPad)
            Button("取消", role: .cancel) { actionPasscode = ""; pendingAction = nil }
            Button("确认") {
                if lock.verifyPasscode(actionPasscode), let act = pendingAction {
                    act()
                } else {
                    errorText = "密码错误。"
                }
                actionPasscode = ""
                pendingAction = nil
            }
        }
```

- [ ] **Step 3: Thread `store` into SettingsMainView and add the link**

`SettingsMainView` currently has **no** `NotieeStore` (only `@StateObject viewModel: SettingsViewModel`). The Security page needs the store, so thread it through from `MeView` (which already has `store`).

3a. In `Notiee/Features/Settings/SettingsMainView.swift`, add a stored property and init parameter:

```swift
struct SettingsMainView: View {
    let store: NotieeStore
    @StateObject private var viewModel: SettingsViewModel
    @AppStorage(UDK.labMarkdownRenderingEnabled) private var markdownRenderingEnabled = false

    @MainActor
    init(store: NotieeStore, settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        self.store = store
        _viewModel = StateObject(wrappedValue: SettingsViewModel(settingsStore: settingsStore))
    }
```

3b. Inside `Section("高级设置")` (starts line ~161), add the link below "管理自定义模型":

```swift
                NavigationLink {
                    SecuritySettingsView(store: store)
                } label: {
                    Label("安全", systemImage: "lock.shield")
                }
```

3c. Update the only call site — `Notiee/Features/Settings/MeView.swift:126`:

```swift
                    SettingsMainView(store: store, settingsStore: settingsStore)
```

`MeView` already declares `@ObservedObject var store: NotieeStore` (line 8), so `store` is in scope there.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Manual verification**

Settings → 高级设置 → 安全 → toggle on → set passcode 123456 → enable Face ID. Kill & relaunch: lock screen appears. Background→foreground: locks. Encrypt a record (Task C9) then return here: it appears under "已加密的拍记"; "解除加密" restores it. Toggle security off: prompts for passcode, then confirms decrypt-all.

- [ ] **Step 6: Commit**

```bash
git add Notiee/Features/Settings/SecuritySettingsView.swift Notiee/Features/Settings/SettingsMainView.swift Notiee/Features/Settings/MeView.swift
git commit -m "feat(security): Security settings page + advanced-settings link"
```

### Task C9: RecordDetailView — 2-item toolbar + encrypt + locked gating

**Files:**
- Modify: `Notiee/Features/Records/RecordDetailView.swift`

- [ ] **Step 1: Replace the toolbar (lines ~51-92)**

Replace the entire `.toolbar { ToolbarItemGroup(placement: .topBarTrailing) { ... } }` block with:

```swift
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Share
                Menu {
                    Button("导出为 .tmn 文件") {
                        Task {
                            do {
                                let url = try await TMNExportService.export(record: viewModel.record, store: viewModel.store)
                                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let window = windowScene.windows.first,
                                   let rootVC = window.rootViewController {
                                    rootVC.present(activityVC, animated: true)
                                }
                            } catch {
                                print("Export failed: \(error.localizedDescription)")
                            }
                        }
                    }
                    ShareLink(
                        item: buildShareContent(),
                        subject: Text(viewModel.record.title),
                        message: Text("分享一条 Notiee 记录")
                    ) {
                        Label("分享...", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.record.isEncrypted)

                // More
                Menu {
                    Button("编辑", systemImage: "pencil") { showEditSheet = true }
                    Button("更多信息", systemImage: "info.circle") { showInfoSheet = true }
                    if viewModel.record.isEncrypted {
                        Button("已加密（在设置中管理）", systemImage: "lock.fill") {}
                            .disabled(true)
                    } else {
                        Button("加密该条拍记", systemImage: "lock") {
                            viewModel.store.encryptRecord(id: viewModel.record.id)
                            dismiss()
                        }
                    }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) {
                        viewModel.deleteRecord()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
```

Rationale: encrypt then `dismiss()` because the persisted record becomes redacted; the user re-opens it through the unlock flow (Step 2). Sharing an encrypted record is disabled to avoid leaking ciphertext-less data.

- [ ] **Step 2: Gate encrypted content behind unlock**

At the top of `RecordDetailView`, add state:

```swift
    @State private var unlockedRecord: NoteRecord?
    @State private var unlockedTodos: [NoteTodo] = []
    @State private var unlockFailed = false
    @StateObject private var appLock = AppLockManager.shared
```

Wrap the `ScrollView { ... }` body so that when `viewModel.record.isEncrypted && unlockedRecord == nil`, a locked placeholder is shown instead. Replace the outer `var body: some View { ScrollView { ... } ... }` opening so that:

```swift
    var body: some View {
        Group {
            if viewModel.record.isEncrypted && unlockedRecord == nil {
                lockedPlaceholder
            } else {
                contentScrollView
            }
        }
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { /* the toolbar block from Step 1 */ }
        // keep existing .sheet(...) modifiers
    }
```

Move the existing `ScrollView { ... }.background(...)` into a computed `private var contentScrollView: some View`. Add:

```swift
    private var lockedPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundColor(.accentColor)
            Text("此拍记已加密").font(.headline)
            Button {
                Task {
                    if await appLock.authenticateWithBiometrics(reason: "查看加密拍记") || !appLock.biometricEnabled {
                        if let result = viewModel.store.decryptedForViewing(viewModel.record) {
                            unlockedRecord = result.record
                            unlockedTodos = result.todos
                        } else {
                            unlockFailed = true
                        }
                    }
                }
            } label: {
                Label("解锁查看", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent)
            if unlockFailed { Text("解锁失败").foregroundColor(.red) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
```

Note: For a full implementation, the content sections (summary/detail/images) should read from `unlockedRecord ?? viewModel.record`. The minimum viable version: after unlock, present the decrypted content in the same layout. If time-boxed, the simplest correct approach is to build a temporary `RecordDetailViewModel(record: unlockedRecord!, store: viewModel.store)` and render `contentScrollView` from it — but note images are still `.enc` on disk, so also update image loading (Step 3). Keep the decrypted plaintext in memory only; never call `store.updateRecord` with it.

- [ ] **Step 3: Decrypt images when viewing**

Find where images load in `RecordDetailView` (search `LocalImageStore.shared.loadImage` / `loadedImages`). For an unlocked encrypted record, image paths end in `.enc`; load them via:

```swift
SecureRecordCodec(crypto: CryptoService.shared()).decryptedImage(atEncryptedPath: path)
```

Guard with `if path.hasSuffix(".enc") { ... } else { LocalImageStore.shared.loadImage(path: path) }`.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Manual verification**

Open a completed photo record → 更多 → 加密该条拍记 → detail dismisses. Reopen from the list: shows "此拍记已加密" → 解锁查看 → Face ID → content + image decrypt in memory. Confirm `Documents/CapturedImages/*.jpg` for that record is gone and a `.enc` sibling + `Documents/EncryptedRecords/<id>.enc` exist (use the simulator container or a debug print).

- [ ] **Step 6: Commit**

```bash
git add Notiee/Features/Records/RecordDetailView.swift
git commit -m "feat(records): 2-item toolbar, encrypt action, locked-view gating"
```

### Task C10: Locked placeholder in list card + thumbnail

**Files:**
- Modify: `Notiee/Components/RecordCardView.swift`, `Notiee/Features/Records/RecordThumbnailView.swift`

- [ ] **Step 1: RecordCardView**

In `RecordCardView.swift`, find where title/summary render. When `record.isEncrypted`, show a lock icon + "已加密拍记" and suppress summary/OCR text. Add near the top of the card's main `VStack`:

```swift
            if record.isEncrypted {
                Label("已加密拍记", systemImage: "lock.fill")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
```

And guard the summary/preview text with `if !record.isEncrypted { ... existing preview ... }`. (The redacted record already has empty summary, so this is mainly to show the lock affordance and avoid a blank card.)

- [ ] **Step 2: RecordThumbnailView**

In `RecordThumbnailView.swift`, the view loads `record.localImagePaths.first` via `LocalImageStore`. When `record.isEncrypted`, skip loading and render a lock placeholder:

```swift
            if record.isEncrypted {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.12))
                    Image(systemName: "lock.fill").foregroundColor(.secondary)
                }
            } else {
                // existing thumbnail loading
            }
```

Adapt to the file's actual structure (it may be a small standalone view taking a `path` or a `record`). If it takes only a `path` string, add an `isEncrypted` init parameter and branch on it; callers pass `record.isEncrypted`.

- [ ] **Step 3: Build + manual verify**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`. Then in the app, the records list shows a lock icon and no preview text/thumbnail for encrypted records.

- [ ] **Step 4: Commit**

```bash
git add Notiee/Components/RecordCardView.swift Notiee/Features/Records/RecordThumbnailView.swift
git commit -m "feat(records): locked placeholder in list card and thumbnail"
```

### Task C11: Skip encrypted records in export / sync / semantic index / search

**Files:**
- Modify: `Notiee/Services/TMNExportService.swift`, `Notiee/Services/ICloudSyncService.swift`, `Notiee/Services/Managers/RecordManager.swift`

- [ ] **Step 1: TMN export guard**

In `TMNExportService.export(record:store:)`, at the top add:

```swift
        if record.isEncrypted {
            throw NSError(domain: "TMNExport", code: 1, userInfo: [NSLocalizedDescriptionKey: "已加密的拍记无法导出，请先在「设置 → 安全」中解除加密。"])
        }
```

(Confirm the function signature/throwing behavior; it is called with `try await` in `RecordDetailView`, which already handles thrown errors. Also, the detail Share menu is disabled for encrypted records in C9, so this is defense-in-depth.)

- [ ] **Step 2: iCloud sync guard**

In `ICloudSyncService.uploadAllRecords(store:)`, filter out encrypted records before uploading:

```swift
        let records = store.records.filter { !$0.isEncrypted }
```

(Find the line that reads `store.records` for upload and add the filter. Encrypted records stay device-local.)

- [ ] **Step 3: Search + semantic index guard**

In `RecordManager.records(matching:)`, exclude encrypted records from text matches (their content is redacted anyway, but exclude explicitly):

```swift
        // inside the filter predicate, add:
        guard !record.isEncrypted else { return false }
```

If the semantic index builder (search `EmbeddingIndex` / `RecordEmbeddingText`) iterates `store.records`, add `where: { !$0.isEncrypted }` there too. Grep: `grep -rn "isDeleted" Notiee/Services/Semantic Notiee/Services/Managers/RecordManager.swift` to find the existing filter sites and mirror the pattern.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme Notiee -destination 'generic/platform=iOS Simulator' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Notiee/Services/TMNExportService.swift Notiee/Services/ICloudSyncService.swift Notiee/Services/Managers/RecordManager.swift
git commit -m "feat(security): exclude encrypted records from export/sync/search/index"
```

---

## Final verification (all features)

- [ ] **Full test suite:** `xcodebuild test -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NotieeTests` — all green (new + existing).
- [ ] **Both targets build:** `xcodebuild -scheme Notiee build` and `xcodebuild -scheme Notiee+ build` succeed.
- [ ] **F1:** Lab → 拍记输出语言 = 自动 → English capture returns English title/summary; 한국어 setting forces Korean.
- [ ] **F2:** Enable security + Face ID → cold start & background-return both lock. Encrypt a record from detail 更多 menu → list shows lock, no plaintext/thumbnail. Inspect app container: `records.json` has no plaintext for that record; `EncryptedRecords/<id>.enc` and `<image>.jpg.enc` exist, original `.jpg` gone. Security page "解除加密" restores it. Disabling security requires passcode and decrypts all.
- [ ] **F3:** Add a text custom model → appears under 文本处理模型 → 我的自定义模型, selectable with checkmark; vision likewise.
- [ ] **Regression:** Existing Chinese users on 自动 still get Chinese output; non-encrypted records, export, sync, and search unaffected.

## Risks / notes
- Encryption mutates disk irreversibly per record. All flows write ciphertext (`.enc` / blob) **before** deleting plaintext, so a failure leaves originals intact; on error the store surfaces `lastPersistenceError`.
- Disabling security decrypts **all** encrypted records (double-confirmed).
- `NSFaceIDUsageDescription` MUST be present in `Notiee copy-Info.plist` or biometric calls crash.
- `SetPasscodeSheet` uses a 6-digit numeric passcode to match the lock pad; keep both at 6 digits.
- Widget target does not read encrypted content; no widget changes needed.
```
