import Foundation

@MainActor
final class ICloudSyncService: ObservableObject {
    static let shared = ICloudSyncService()

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var lastError: String?

    enum SyncError: LocalizedError {
        case iCloudNotAvailable
        case noRecords
        case noCloudData
        case fileError(String)
        case downloadTimeout

        var errorDescription: String? {
            switch self {
            case .iCloudNotAvailable: return "iCloud 不可用，请检查 iCloud 设置。"
            case .noRecords: return "本地暂无记录可同步。"
            case .noCloudData: return "iCloud 中暂无同步数据。"
            case .fileError(let msg): return "文件操作失败：\(msg)"
            case .downloadTimeout: return "iCloud 下载超时，请检查网络后重试。"
            }
        }
    }

    private let syncDirectory = "NotieeSync"
    private let fileCoordinator = NSFileCoordinator(filePresenter: nil)

    private var containerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    private var syncURL: URL? {
        containerURL?.appendingPathComponent(syncDirectory)
    }

    private init() {
        if let interval = UserDefaults.standard.object(forKey: UDK.icloudLastSyncDate) as? TimeInterval {
            lastSyncDate = Date(timeIntervalSince1970: interval)
        }
    }

    func isAvailable() -> Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func uploadAllRecords(store: NotieeStore) async throws -> Int {
        guard let syncURL = syncURL else {
            throw SyncError.iCloudNotAvailable
        }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        try await createSyncDirectoryIfNeeded(at: syncURL)

        let records = store.sortedRecords.filter { !$0.isEncrypted }
        guard !records.isEmpty else {
            throw SyncError.noRecords
        }

        var uploadedCount = 0

        for record in records {
            do {
                let tmnURL = try await TMNExportService.export(record: record, store: store)
                let destURL = syncURL.appendingPathComponent("\(record.id.uuidString).tmn")
                try await coordinatedCopy(from: tmnURL, to: destURL)
                uploadedCount += 1
            } catch {
                print("Failed to upload record \(record.id): \(error)")
            }
        }

        lastSyncDate = Date()
        persistLastSyncDate()
        return uploadedCount
    }

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

        try await downloadCloudFiles(at: syncURL)

        let files = try coordinatedContentsOfDirectory(at: syncURL)
        let tmnFiles = files.filter { $0.pathExtension == "tmn" }

        guard !tmnFiles.isEmpty else {
            throw SyncError.noCloudData
        }

        var importedCount = 0

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
                        updated.keyPoints = record.keyPoints
                        updated.definitions = record.definitions
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

    // MARK: - Private Helpers

    private func createSyncDirectoryIfNeeded(at url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var error: NSError?
            fileCoordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error) { writeURL in
                if !FileManager.default.fileExists(atPath: writeURL.path) {
                    do {
                        try FileManager.default.createDirectory(at: writeURL, withIntermediateDirectories: true, attributes: nil)
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                }
                continuation.resume()
            }
            if let error {
                continuation.resume(throwing: error)
            }
        }
    }

    private func coordinatedCopy(from source: URL, to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var error: NSError?
            fileCoordinator.coordinate(writingItemAt: destination, options: .forReplacing, error: &error) { writeURL in
                do {
                    if FileManager.default.fileExists(atPath: writeURL.path) {
                        try FileManager.default.removeItem(at: writeURL)
                    }
                    try FileManager.default.copyItem(at: source, to: writeURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            if let error {
                continuation.resume(throwing: error)
            }
        }
    }

    private func coordinatedContentsOfDirectory(at url: URL) throws -> [URL] {
        var result: [URL] = []
        var coordinatorError: NSError?
        var accessError: Error?

        fileCoordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { readURL in
            do {
                result = try FileManager.default.contentsOfDirectory(at: readURL, includingPropertiesForKeys: nil)
            } catch {
                accessError = error
            }
        }

        if let coordinatorError { throw coordinatorError }
        if let accessError { throw accessError }
        return result
    }

    private func downloadCloudFiles(at url: URL) async throws {
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])

        let pendingFiles = files.filter { file in
            guard let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus else {
                return false
            }
            return status == .notDownloaded
        }

        guard !pendingFiles.isEmpty else { return }

        for file in pendingFiles {
            do {
                try FileManager.default.startDownloadingUbiquitousItem(at: file)
            } catch {
                print("Failed to trigger download for \(file.lastPathComponent): \(error)")
            }
        }

        try await waitForDownloads(at: url)
    }

    private func waitForDownloads(at url: URL) async throws {
        let maxWait: TimeInterval = 30
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < maxWait {
            let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemDownloadingErrorKey])

            let allDownloaded = files.allSatisfy { file in
                guard let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus else {
                    return true
                }
                return status != .notDownloaded
            }

            if allDownloaded {
                return
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        throw SyncError.downloadTimeout
    }

    private func persistLastSyncDate() {
        if let date = lastSyncDate {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: UDK.icloudLastSyncDate)
        }
    }
}
