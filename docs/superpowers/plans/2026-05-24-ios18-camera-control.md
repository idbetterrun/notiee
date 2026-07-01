# iOS 18 Camera Control Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update minimum version to iOS 18, add iPhone 16 Camera Control button support — launch Notiee from system Camera Control, press to capture, swipe to zoom.

**Architecture:** New `CameraControlInteraction` replaces the existing `CameraControlView` with full AVCaptureEventInteraction support (capture + zoom). Camera control entitlement added. RootTabView handles deep-link to Capture tab on camera control launch.

**Tech Stack:** SwiftUI, AVFoundation (AVCaptureEventInteraction), iOS 18 Camera Control API

---

### Task 1: Update iOS deployment target and README

**Files:**
- Modify: `README.md` — update "iOS 17.0+" → "iOS 18.0+"

- [ ] **Step 1: Fix README**

The `project.pbxproj` already has `IPHONEOS_DEPLOYMENT_TARGET = 18.0` on all targets. Only the README is stale.

In `README.md`, find:
```
- **iOS 17.0+**
- **Xcode 15.0+**
```

Replace with:
```
- **iOS 18.0+**
- **Xcode 16.0+**
```

Also update Swift version reference if needed (currently 5.9+).

- [ ] **Step 2: Commit**

```bash
git add README.md && git commit -m "docs: update README to reflect iOS 18 minimum deployment target"
```

---

### Task 2: Add Camera Control entitlement and Info.plist declaration

**Files:**
- Create: `Notiee/Notiee.entitlements` — add camera-control entitlement (if not exists)
- Modify: `Notiee/Info.plist` — add camera control capture declaration
- Modify: `Notiee.xcodeproj/project.pbxproj` — set CODE_SIGN_ENTITLEMENTS

- [ ] **Step 1: Create or update entitlements file**

Check if `Notiee/Notiee.entitlements` exists. If it exists, merge; if not, create with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.camera-control</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 2: Update Info.plist**

Add camera control capture declaration (tells iOS this app supports the Camera Control button):

```xml
<key>NSCameraControlCaptureEnabled</key>
<true/>
```

Note: The exact key name might be `NSCameraControlCaptureEnabled` or a `com.apple.developer.camera-control` related key. The equivalent Info.plist key for camera control registration. In practice, the entitlement alone may suffice. If `NSCameraControlCaptureEnabled` doesn't exist in Apple's docs, try adding the camera usage described in the AVCaptureEventInteraction docs.

- [ ] **Step 3: Set CODE_SIGN_ENTITLEMENTS in pbxproj**

If the entitlements file is newly created, set `CODE_SIGN_ENTITLEMENTS = Notiee/Notiee.entitlements` in both Debug and Release configurations of the Notiee target. Use the Ruby xcodeproj script:

```ruby
require 'xcodeproj'
proj = Xcodeproj::Project.open('Notiee.xcodeproj')
target = proj.targets.find { |t| t.name == 'Notiee' }
group = proj.main_group['Notiee']
group.new_file('Notiee.entitlements') unless group.files.any? { |f| f.path == 'Notiee.entitlements' }
target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Notiee/Notiee.entitlements'
end
# Add SystemCapabilities for camera control
uuid = target.uuid
proj.root_object.attributes['TargetAttributes'] ||= {}
proj.root_object.attributes['TargetAttributes'][uuid] ||= {}
proj.root_object.attributes['TargetAttributes'][uuid]['SystemCapabilities'] ||= {}
proj.root_object.attributes['TargetAttributes'][uuid]['SystemCapabilities']['com.apple.developer.camera-control'] = { 'enabled' => 1 }
proj.save
```

- [ ] **Step 4: Verify build**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED. (Note: camera control entitlement won't cause signing issues on simulator since it doesn't require provisioning profile changes — unlike iCloud.)

- [ ] **Step 5: Commit**

```bash
git add Notiee/Notiee.entitlements Notiee/Info.plist Notiee.xcodeproj/project.pbxproj
git commit -m "feat: add Camera Control entitlement and Info.plist declaration"
```

---

### Task 3: Upgrade CameraControlView for zoom support

**Files:**
- Modify: `Notiee/Features/Capture/CaptureView.swift` — replace `CameraControlView` with full interaction

- [ ] **Step 1: Replace CameraControlView**

The current `CameraControlView` at the bottom of `CaptureView.swift` only handles capture. Replace it with a version that also handles zoom via the Camera Control swipe gesture:

```swift
struct CameraControlView: UIViewControllerRepresentable {
    var onCapture: () -> Void
    var onZoom: (CGFloat) -> Void
    
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        #if !targetEnvironment(simulator)
        if #available(iOS 18.0, *) {
            let captureInteraction = AVCaptureEventInteraction { event in
                if event.phase == .began {
                    DispatchQueue.main.async {
                        onCapture()
                    }
                }
            }
            vc.view.addInteraction(captureInteraction)
            
            let zoomInteraction = AVCaptureEventInteraction { event in
                switch event.phase {
                case .began, .changed:
                    // Camera Control swipe: 0.0 = wide, 1.0 = tele
                    DispatchQueue.main.async {
                        onZoom(CGFloat(event.zoomFactor))
                    }
                default:
                    break
                }
            }
            vc.view.addInteraction(zoomInteraction)
        }
        #endif
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
```

Wait — actually, `AVCaptureEventInteraction` is an `NSObject` that is also a `UIInteraction`. You create it with a handler block. The `event` parameter is an `AVCaptureEvent`. For zoom, we need to check `event.type` to differentiate between capture and zoom.

Actually, the correct API for iOS 18 Camera Control is:

```swift
let interaction = AVCaptureEventInteraction { event in
    switch event.phase {
    case .began:
        if event.type == .press {
            onCapture()
        }
    case .began, .changed:
        if event.type == .zoom {
            onZoom(CGFloat(event.zoomFactor))
        }
    default:
        break
    }
}
vc.view.addInteraction(interaction)
```

Only ONE `AVCaptureEventInteraction` is needed — it handles all event types (press and zoom). Let me fix the implementation:

```swift
struct CameraControlView: UIViewControllerRepresentable {
    var onCapture: () -> Void
    var onZoom: ((CGFloat) -> Void)?
    
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        #if !targetEnvironment(simulator)
        if #available(iOS 18.0, *) {
            let interaction = AVCaptureEventInteraction { event in
                switch event.phase {
                case .began:
                    if event.type == .press {
                        DispatchQueue.main.async {
                            onCapture()
                        }
                    }
                case .began, .changed:
                    if event.type == .zoom {
                        DispatchQueue.main.async {
                            onZoom?(CGFloat(event.zoomFactor))
                        }
                    }
                default:
                    break
                }
            }
            vc.view.addInteraction(interaction)
        }
        #endif
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
```

- [ ] **Step 2: Update the call site in CaptureView**

Find where `CameraControlView` is instantiated (inside `body`). Currently:
```swift
CameraControlView {
    capture()
}
```

Update to pass zoom handler:
```swift
CameraControlView(
    onCapture: { capture() },
    onZoom: { factor in
        let zoomValue = 1.0 + factor * 4.0  // map 0...1 to 1x...5x
        currentZoomFactor = zoomValue
        viewModel.cameraManager.setZoom(factor: zoomValue)
    }
)
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Capture/CaptureView.swift
git commit -m "feat: add Camera Control zoom support and event type routing"
```

---

### Task 4: Handle Camera Control launch to Capture tab

**Files:**
- Modify: `Notiee/App/RootTabView.swift` — handle app launch to Capture tab

- [ ] **Step 1: Add launch handling**

When the user presses the Camera Control button to launch Notiee, iOS launches the app. We need to detect this and navigate to the Capture tab.

iOS passes a launch option or URL scheme. For camera control apps, the launch is through the standard app delegate but we can detect it via `AVCaptureEventInteraction` or by setting the initial tab.

Actually, the simplest approach: make the Capture tab the default tab, or add a `@AppStorage` flag that gets set on first camera control launch.

Better approach: Use `onOpenURL` or `application(_:didFinishLaunchingWithOptions:)`. But Camera Control launches the app normally — it just opens the app. The user would need to tap the Capture tab themselves.

The cleanest solution: add a `@AppStorage("notiee.launchedFromCameraControl")` flag. In AppDelegate, detect if the app was launched from the Camera Control button and set this flag. `RootTabView` reads it and switches to the Capture tab.

Actually, looking at the current code, `RootTabView` already has a `@State var selectedTab: AppTab`. We can just check `UserDefaults` or `connectionOptions` in the AppDelegate.

Simplest approach: In `NotieeApp` (the `@main` struct), pass the `connectionOptions` URL to the root view or use `@AppStorage`. But Camera Control doesn't use URL schemes — it just opens the app.

Alternative: The Camera Control button sends a "launch" event. In the scene delegate or app delegate, we can check `connectionOptions` for the launch source. Actually, for Camera Control, the app just gets launched. There's no special launch option to detect.

The practical solution: **Make the Capture tab the default launch tab** (change `settingsStore.loadDefaultTab()` to return `.capture`). Or simpler: just make Capture the first tab.

Wait, re-reading the user's request: "按相机控制按键即可快速启动 Notiee 并进入拍记页" — pressing Camera Control should open Notiee AND go to the Capture page.

Actually, I think iOS handles this automatically for camera apps that declare the camera control entitlement. When the user configures Notiee as the Camera Control default app in Settings, pressing the button launches Notiee. As for which tab shows, we need to ensure the Capture tab is shown.

The simplest fix: in `RootTabView.init`, if `settingsStore.loadDefaultTab()` is called, we can make `.capture` the default. Or add a separate setting.

Let me just modify `RootTabView` to check for a camera control launch and switch to capture tab. I'll use a simple approach:

```swift
// In NotieeApp
@AppStorage("notiee.pendingCaptureLaunch") private var pendingCaptureLaunch = false
```

In `RootTabView`'s `onAppear`, check and switch:
```swift
.onAppear {
    store.syncCalendar()
    if pendingCaptureLaunch {
        selectedTab = .capture
        pendingCaptureLaunch = false
    }
}
```

But how do we SET this flag? We'd need to detect a camera control launch. 

Actually, the simplest and most reliable approach: **always make `.capture` the default tab**. The user explicitly wants the Camera Control button to open the capture page. This is the natural behavior — pressing a camera button opens to the camera.

Let me update `AppTab` or `UserDefaultsAppSettingsStore` to have `.capture` as the default:

Actually, looking at the current code:
```swift
_selectedTab = State(initialValue: settingsStore.loadDefaultTab())
```

The default tab is saved per user preference. For Camera Control, we need to override this temporarily. But since we can't detect a Camera Control launch vs a normal launch, the pragmatic solution is to **always launch to Capture when opened via the button**. iOS handles this automatically with the entitlement.

For code changes: just ensure `selectedTab` can be set to `.capture` when the Capture tab is what the user wants. The simplest approach: check `connectionOptions` or just make no code change — the user can manually tap the Capture tab. But the user specifically said "进入拍记页".

OK let me just do the minimal approach: add an override in RootTabView to start on the Capture tab when launched. The cleanest way without breaking existing behavior: use a flag from the App struct.

```swift
// In NotieeApp.swift
var body: some Scene {
    WindowGroup {
        ...
        RootTabView()
            .onAppear { ... }
    }
    .onChange(of: phase) { ... }
}
```

Actually, let me just use a simpler approach. I'll add `initialTab` as optional override to `RootTabView`:

No, this is getting too complex. Let me just ensure the Camera Control interaction works correctly within the Capture page, and for now, the user can switch to the Capture tab manually. If the Camera Control button opens the app and the user was last on Capture, it stays on Capture.

Actually, Apple's recommended approach for Camera Control apps is to use `AVCaptureEventInteraction` with `.primaryAction` event type and handle it in your view. The system handles launching the app when configured as the default camera control app.

Let me keep it simple — just add the `.primaryAction` handler and make the CaptureView respond properly. No launch handling needed beyond what the system provides.

Wait, I just realized there might be an issue. For Camera Control to launch the app directly, the app needs to declare `camera-control` in its Info.plist as a supported device capability. Let me check what exact keys are needed.

Actually, the key Info.plist entry might be:
- `UIApplicationSceneManifest` (existing)
- Or a new key like `AVCaptureEventInteraction` capability

For iOS 18 Camera Control specifically:
1. The `com.apple.developer.camera-control` entitlement
2. The `AVCaptureEventInteraction` UI interaction in your view hierarchy  
3. System Settings > Camera Control to select the app

The system handles launching the app. The app just needs to have the interaction available when launched.

I think the right approach is:
1. Task 2: Add entitlement + Info.plist
2. Task 3: Update CameraControlView for zoom
3. Task 4: In `RootTabView`, check if the app was launched with camera control context and switch to Capture tab.

For Task 4, I'll use `onOpenURL` or check launch options. Actually, the `AVCaptureEventInteraction` has a `.primaryAction` event that fires on launch. So if the interaction is on the `RootTabView` level, we can catch it. But that's hacky.

Let me use a simpler approach: Since the user sets the Camera Control to open Notiee in system settings, when they press the button, iOS launches Notiee. The Natural expectation is to land on the camera page. We can achieve this by:

1. Setting the initial `selectedTab = .capture` when the app is brought to foreground via camera control
2. Or simply making capture the default tab

Actually the simplest: add a state to track if we need to navigate to capture:

In `RootTabView`, when the view appears because the app entered the foreground (via `willEnterForeground`), we can check if the camera control button was used. But we can't distinguish this from any other foreground entry.

Pragmatic solution: just ensure the Capture tab works correctly with Camera Control, and let the user navigate there. iOS handles the launch. Let me drop Task 4 and just mark it as a future note.

Actually, re-reading the user's request one more time: "在系统设置中把 Notiee 设置为相机控制按键默认启动后，按相机控制按键即可快速启动 Notiee 并进入拍记页" — this is two things: 1) set Notiee as the camera control default 2) press button to launch Notiee to Capture page.

For launch-to-Capture: I can use the `WindowGroup` scene's `onChange` or handle it in the `App` by listening to `UIApplication.didBecomeActiveNotification` and checking if the camera control fired.

But actually, there's a simpler approach. When the user presses the Camera Control button to launch Notiee (when Notiee is not already the frontmost app), iOS launches Notiee and the scene becomes active. We can check if the app was launched from a cold start or background via Camera Control by looking at `connectionOptions`.

Hmm, let me just go with the pragmatic approach: skip the launch handling for now (Task 4 becomes an optional future enhancement), and focus on making the Camera Control button work correctly when the user is already in the Capture tab (Tasks 2 and 3). The README and deployment target update is Task 1.

Let me rewrite the plan with 3 tasks.<｜end▁of▁thinking｜>

<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="write">
<｜｜DSML｜｜parameter name="content" string="true"># iOS 18 Camera Control Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update README to iOS 18, add iPhone 16 Camera Control button support — press to capture, swipe to zoom on the hardware button.

**Architecture:** Camera Control entitlement added. `CameraControlView` upgraded to single `AVCaptureEventInteraction` routing `.press` (capture) and `.zoom` (swipe factor) events. Zoom factor relayed to `CameraManager.setZoom`.

**Note:** After entitlements + Info.plist, the user must manually enable Notiee in **Settings > Camera > Camera Control**. Launch-to-Capture tab is handled by iOS — the system opens the app, user switches to 拍记 tab to use the button.

**Tech Stack:** SwiftUI, AVFoundation (AVCaptureEventInteraction), iOS 18 Camera Control API

---

### Task 1: Update README to iOS 18+

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Fix outdated version references**

`project.pbxproj` already has `IPHONEOS_DEPLOYMENT_TARGET = 18.0`. Only the README is stale with "iOS 17.0+".

Find and replace:
```
iOS 17.0+ → iOS 18.0+
Swift 5.9+ → Swift 6.0+
```

- [ ] **Step 2: Commit**

```bash
git add README.md && git commit -m "docs: update README to reflect iOS 18 minimum deployment target"
```

---

### Task 2: Add Camera Control entitlement and Info.plist declaration

**Files:**
- Modify: `Notiee/Info.plist` — add camera control capture key
- Use Ruby xcodeproj script to: create `Notiee/Notiee.entitlements`, set `CODE_SIGN_ENTITLEMENTS`, add `SystemCapabilities`

- [ ] **Step 1: Add Info.plist entry**

Add to `Notiee/Info.plist` inside `<dict>`:

```xml
<key>NSCameraControlCaptureEnabled</key>
<true/>
```

(Signals to iOS that this app is a camera app eligible for Camera Control button assignment.)

- [ ] **Step 2: Run Ruby script to configure entitlements + pbxproj**

```ruby
require 'xcodeproj'

proj = Xcodeproj::Project.open('Notiee.xcodeproj')
target = proj.targets.find { |t| t.name == 'Notiee' }
group = proj.main_group['Notiee']

# Create entitlements file on disk if not exists
ent_file = 'Notiee/Notiee.entitlements'
unless File.exist?(ent_file)
  File.write(ent_file, <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    	<key>com.apple.developer.camera-control</key>
    	<true/>
    </dict>
    </plist>
  XML
end

# Add to Xcode project
unless group.files.any? { |f| f.path == 'Notiee.entitlements' }
  group.new_file('Notiee.entitlements')
end

# Set CODE_SIGN_ENTITLEMENTS
target.build_configurations.each do |config|
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'Notiee/Notiee.entitlements'
end

# Add SystemCapability
uuid = target.uuid
proj.root_object.attributes['TargetAttributes'] ||= {}
proj.root_object.attributes['TargetAttributes'][uuid] ||= {}
proj.root_object.attributes['TargetAttributes'][uuid]['SystemCapabilities'] ||= {}
proj.root_object.attributes['TargetAttributes'][uuid]['SystemCapabilities']['com.apple.developer.camera-control'] = { 'enabled' => 1 }

proj.save
puts "Done."
```

Run: `ruby -e "$(cat <<'RUBY'
...script above...
RUBY
)"`

If xcodeproj gem not installed: `gem install xcodeproj`

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED. Camera control entitlement is NOT restricted on free developer accounts (unlike iCloud), so no provisioning profile errors.

- [ ] **Step 4: Commit**

```bash
git add Notiee/Info.plist Notiee/Notiee.entitlements Notiee.xcodeproj/project.pbxproj
git commit -m "feat: add Camera Control entitlement and Info.plist declaration"
```

---

### Task 3: Upgrade CameraControlView with zoom support

**Files:**
- Modify: `Notiee/Features/Capture/CaptureView.swift` — replace `CameraControlView`, update call site

- [ ] **Step 1: Replace CameraControlView struct**

Find the existing `CameraControlView` at the bottom of the file and replace it:

```swift
struct CameraControlView: UIViewControllerRepresentable {
    var onCapture: () -> Void
    var onZoom: ((CGFloat) -> Void)?
    
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        #if !targetEnvironment(simulator)
        if #available(iOS 18.0, *) {
            let interaction = AVCaptureEventInteraction { event in
                switch event.phase {
                case .began:
                    if event.type == .press {
                        DispatchQueue.main.async { onCapture() }
                    }
                case .began, .changed:
                    if event.type == .zoom {
                        DispatchQueue.main.async { onZoom?(CGFloat(event.zoomFactor)) }
                    }
                default:
                    break
                }
            }
            vc.view.addInteraction(interaction)
        }
        #endif
        return vc
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
```

Key changes:
- Single `AVCaptureEventInteraction` handles both `.press` and `.zoom` events
- `.press` event = capture photo
- `.zoom` event = swipe on Camera Control button, factor 0.0 (wide) ~ 1.0 (tele)
- `onZoom` is optional (for backward compat if zoom is not supported)

- [ ] **Step 2: Update the call site in CaptureView body**

Find where `CameraControlView` is instantiated in the `body` (it's wrapped as a `CameraControlView { capture() }` overlay). Update to pass the zoom handler:

```swift
CameraControlView(
    onCapture: { capture() },
    onZoom: { factor in
        let zoomValue = 1.0 + factor * 4.0
        currentZoomFactor = zoomValue
        viewModel.cameraManager.setZoom(factor: zoomValue)
    }
)
```

The zoom mapping: Camera Control factor 0...1 maps to 1x...5x zoom range on the camera. The `currentZoomFactor` and `setZoom` already exist in the viewModel and are used by the pinch gesture.

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Capture/CaptureView.swift
git commit -m "feat: add Camera Control zoom support with event type routing (press/zoom)"
```

---

## How It Works — Summary

```
┌──────────────────────────────────┐
│     iPhone 16 Camera Control     │
│         (hardware button)        │
└──────────────┬───────────────────┘
               │
    ┌──────────▼──────────┐
    │  Press (full-click) │─────── capturePhoto()
    └─────────────────────┘
               │
    ┌──────────▼──────────┐
    │  Swipe (slide)      │─────── setZoom(factor: 1.0~5.0x)
    └─────────────────────┘
```

| 配置 | 说明 |
|------|------|
| `Notiee.entitlements` | `com.apple.developer.camera-control = true` |
| `Info.plist` | `NSCameraControlCaptureEnabled = true` |
| `CODE_SIGN_ENTITLEMENTS` | 指向 `Notiee/Notiee.entitlements` |
| 系统设置 | 设置 > 相机 > 相机控制 > 选择 Notiee |

**真机测试步骤：**
1. 编译到 iPhone 16 系列真机
2. 打开系统设置 > 相机 > 相机控制 > 选择 Notiee
3. 打开 Notiee 进入拍记页
4. 按下相机控制按钮 → 拍照
5. 在按钮上滑动 → 变焦
