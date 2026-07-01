# iCloud Manual Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add manual iCloud Drive sync — upload local `.tmn` records to `iCloud/NotieeSync/`, download from cloud and merge with ID-based dedup and `editedAt` conflict resolution.

**Architecture:** New `ICloudSyncService` handles all iCloud I/O. `LabFeaturesView` replaces the placeholder toggle with upload/download buttons + progress UI. UUID-based filenames (`{recordID}.tmn`) provide natural dedup; `editedAt` comparison resolves conflicts.

**Tech Stack:** SwiftUI, FileManager (ubiquityContainer), ZIPFoundation (existing), TMNExportService/TMNImportService (existing)

---

### Task 1: Create ICloudSyncService

**Files:**
- Create: `Notiee/Services/ICloudSyncService.swift`
- Modify: `Notiee.xcodeproj/project.pbxproj` — add file reference

- [ ] **Step 1: Create the service skeleton**

New file `Notiee/Services/ICloudSyncService.swift`:

```swift
import Foundation

@MainActor
final class ICloudSyncService: ObservableObject {
    static let shared = ICloudSyncService()
    
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var lastError: String?
    
    private let syncDirectory = "NotieeSync"
    
    private var containerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }
    
    private var syncURL: URL? {
        containerURL?.appendingPathComponent(syncDirectory)
    }
    
    private init() {}
    
    func isAvailable() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
}
```

- [ ] **Step 2: Add upload method**

```swift
func uploadAllRecords(store: NotieeStore) async throws -> Int {
    guard let syncURL = syncURL else {
        throw SyncError.iCloudNotAvailable
    }
    
    isSyncing = true
    lastError = nil
    defer { isSyncing = false }
    
    // Create directory if needed
    if !FileManager.default.fileExists(atPath: syncURL.path) {
        try FileManager.default.createDirectory(at: syncURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    let records = store.sortedRecords
    guard !records.isEmpty else {
        throw SyncError.noRecords
    }
    
    var uploadedCount = 0
    
    for record in records {
        do {
            let tmnURL = try await TMNExportService.export(record: record, store: store)
            let destURL = syncURL.appendingPathComponent("\(record.id.uuidString).tmn")
            
            // Remove old file if exists (overwrite)
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            
            // Copy to iCloud — this triggers upload
            try FileManager.default.copyItem(at: tmnURL, to: destURL)
            uploadedCount += 1
        } catch {
            print("Failed to upload record \(record.id): \(error)")
        }
    }
    
    lastSyncDate = Date()
    persistLastSyncDate()
    return uploadedCount
}
```

- [ ] **Step 3: Add download and merge method**

```swift
func downloadAndMerge(store: NotieeStore) async throws -> Int {
    guard let syncURL = syncURL else {
        throw SyncError.iCloudNotAvailable
    }
    
    guard FileManager.default.fileExists(atPath: syncURL.path) else {
        throw SyncError.noCloudData
    }
    
    isSyncing = true
    lastError = nil
    defer { isSyncing = false }
    
    // Force iCloud download of any not-yet-downloaded files
    try downloadCloudFiles(at: syncURL)
    
    let files = try FileManager.default.contentsOfDirectory(at: syncURL, includingPropertiesForKeys: nil)
    let tmnFiles = files.filter { $0.pathExtension == "tmn" }
    
    guard !tmnFiles.isEmpty else {
        throw SyncError.noCloudData
    }
    
    var importedCount = 0
    var existingRecordIDs = Set(store.sortedRecords.map { $0.id })
    
    for tmnURL in tmnFiles {
        do {
            let (record, todos) = try await TMNImportService.importTMN(url: tmnURL)
            
            if let existing = store.sortedRecords.first(where: { $0.id == record.id }) {
                let cloudDate = record.editedAt ?? record.capturedAt
                let localDate = existing.editedAt ?? existing.capturedAt
                
                if cloudDate > localDate {
                    var updated = existing
                    updated.eventID = record.eventID
                    updated.folderID = record.folderID
                    updated.capturedAt = record.capturedAt
                    updated.localImagePaths = record.localImagePaths
                    updated.title = record.title
                    updated.ocrText = record.ocrText
                    updated.summary = record.summary
                    updated.detailedContent = record.detailedContent
                    updated.processingState = record.processingState
                    updated.editedAt = record.editedAt
                    updated.modelsUsed = record.modelsUsed
                    updated.tokenUsage = record.tokenUsage
                    updated.deviceName = record.deviceName
                    store.updateRecord(updated)
                    
                    store.replaceTodos(for: record.id, with: todos)
                    importedCount += 1
                }
            } else {
                store.addRecord(record)
                for todo in todos {
                    store.addTodo(todo)
                }
                existingRecordIDs.insert(record.id)
                importedCount += 1
            }
        } catch {
            print("Failed to import \(tmnURL.lastPathComponent): \(error)")
        }
    }
    
    lastSyncDate = Date()
    persistLastSyncDate()
    return importedCount
}

private func downloadCloudFiles(at url: URL) throws {
    guard let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey],
        options: [.skipsHiddenFiles],
        errorHandler: nil
    ) else { return }
    
    for case let fileURL as URL in enumerator {
        var isDownloaded = false
        do {
            try fileURL.startAccessingSecurityScopedResource()
            defer { fileURL.stopAccessingSecurityScopedResource() }
            
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            isDownloaded = true
        } catch {
            if !isDownloaded {
                print("Failed to trigger download for \(fileURL.lastPathComponent): \(error)")
            }
        }
    }
}
```

- [ ] **Step 4: Add error enum and persistence helpers**

```swift
enum SyncError: LocalizedError {
    case iCloudNotAvailable
    case noRecords
    case noCloudData
    case fileError(String)
    
    var errorDescription: String? {
        switch self {
        case .iCloudNotAvailable: return "iCloud 不可用，请检查 iCloud 设置。"
        case .noRecords: return "本地暂无记录可同步。"
        case .noCloudData: return "iCloud 中暂无同步数据。"
        case .fileError(let msg): return "文件操作失败：\(msg)"
        }
    }
}

private func persistLastSyncDate() {
    if let date = lastSyncDate {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "notiee.icloudLastSyncDate")
    }
}
```

Edit: add this after the `ContainerURL` in the init.

- [ ] **Step 5: Add file to Xcode project and build**

Use a similar approach to the Ruby script or manual pbxproj editing to add `ICloudSyncService.swift` to the Models group (or Services group) in the Xcode project.

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 6: Commit**

```bash
git add Notiee/Services/ICloudSyncService.swift Notiee.xcodeproj/project.pbxproj
git commit -m "feat: add ICloudSyncService with upload/download and editedAt conflict resolution"
```

---

### Task 2: Update LabFeaturesView with sync buttons

**Files:**
- Modify: `Notiee/Features/Settings/LabFeaturesView.swift`

- [ ] **Step 1: Replace the placeholder toggle with sync UI**

Read the current `LabFeaturesView.swift`. Replace the `Section` containing the "手动同步 iCloud" toggle with:

```swift
Section {
    if ICloudSyncService.shared.isAvailable() {
        HStack {
            Label("iCloud 同步", systemImage: "icloud.and.arrow.up")
            Spacer()
            if let date = ICloudSyncService.shared.lastSyncDate {
                Text(date.formatted(.relative(presentation: .numeric)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        
        Button {
            Task {
                do {
                    let count = try await ICloudSyncService.shared.uploadAllRecords(store: store)
                    print("Uploaded \(count) records to iCloud")
                } catch {
                    print("Upload failed: \(error.localizedDescription)")
                }
            }
        } label: {
            HStack {
                if ICloudSyncService.shared.isSyncing {
                    ProgressView()
                        .padding(.trailing, 4)
                }
                Text("上传同步")
                Spacer()
                Image(systemName: "arrow.up.doc.fill")
            }
        }
        .disabled(ICloudSyncService.shared.isSyncing)
        
        Button {
            Task {
                do {
                    let count = try await ICloudSyncService.shared.downloadAndMerge(store: store)
                    print("Downloaded and merged \(count) records from iCloud")
                } catch {
                    print("Download failed: \(error.localizedDescription)")
                }
            }
        } label: {
            HStack {
                if ICloudSyncService.shared.isSyncing {
                    ProgressView()
                        .padding(.trailing, 4)
                }
                Text("下载同步")
                Spacer()
                Image(systemName: "arrow.down.doc.fill")
            }
        }
        .disabled(ICloudSyncService.shared.isSyncing)
    } else {
        HStack {
            Label("iCloud 同步不可用", systemImage: "icloud.slash")
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }
} footer: {
    Text("通过 iCloud Drive 在设备间同步记录。使用 UUID 去重，editedAt 版本比较解决冲突。")
}
```

Also remove the old `@AppStorage("labICloudSyncEnabled") private var iCloudSyncEnabled = false` since we no longer need a toggle.

- [ ] **Step 2: Inject NotieeStore dependency if needed**

Check that `LabFeaturesView` already has `@ObservedObject var store: NotieeStore`. If not, add it to the init. (Looking at the current code, it should already have `store`.)

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 4: Commit**

```bash
git add Notiee/Features/Settings/LabFeaturesView.swift
git commit -m "feat: add iCloud upload/download buttons to LabFeaturesView"
```

---

## Final Verification

- [ ] **Build and check all files:**

```bash
xcodebuild -project Notiee.xcodeproj -scheme Notiee -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```

Expected: **BUILD SUCCEEDED**

---

## How It Works — Summary

```
┌─────────────────────────────┐    ┌─────────────────────────────┐
│         Device A            │    │      iCloud/NotieeSync/     │
│    (records in store)       │    │                             │
│                             │    │  A1B2C3D4.tmn  (record 1)   │
│  [Upload Sync] ─────────────┼───▶│  E5F6G7H8.tmn  (record 2)   │
│                             │    │  ...                        │
│                             │    │                             │
│         Device B            │    │                             │
│    (records in store)       │    │                             │
│                             │    │                             │
│  [Download Sync] ◀──────────┼────│                             │
│    merge by ID+editedAt     │    │                             │
└─────────────────────────────┘    └─────────────────────────────┘
```

**Dedup:** `{recordID}.tmn` filename = same ID overwrites, no duplicates.
**Conflict:** Compare `editedAt`; cloud newer → overwrite local; local newer → skip.
**Safety:** No auto-delete on download (deleted tracking is a future enhancement).
**Fallback:** `capturedAt` used when `editedAt` is nil.
