import SwiftUI
import ZIPFoundation
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @ObservedObject var store: NotieeStore
    
    @State private var isExporting = false
    @State private var exportURL: URL? = nil
    @State private var showingExportShareSheet = false
    
    @State private var showingImportPicker = false
    @State private var isImporting = false
    @State private var importPreviewData: [PreviewData] = []
    @State private var showingImportPreview = false

    @State private var showingSingleTMNPicker = false
    @State private var singleTMNPreview: PreviewData?
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(NotieeColors.themed(.blue))
                        .padding(.top, 8)
                    
                    Text("备份与恢复")
                        .font(.headline)
                    
                    Text("通过 ZIP 压缩包一键导出所有记录，或从包含 .tmn 文件的 ZIP 中批量恢复。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            
            Section {
                Button {
                    exportAllRecords()
                } label: {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .padding(.trailing, 8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("一键导出所有记录")
                    }
                }
                .disabled(isExporting || isImporting || store.records.isEmpty)
            } footer: {
                Text("将本地所有拍记记录打包为一个 ZIP 文件。")
            }
            
            Section {
                Button {
                    showingImportPicker = true
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .padding(.trailing, 8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text("从 ZIP 压缩包恢复")
                    }
                }
                .disabled(isExporting || isImporting)
            } footer: {
                Text("选择一个包含 .tmn 记录文件的 ZIP 压缩包恢复到本地。")
            }

            Section {
                Button {
                    showingSingleTMNPicker = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                        Text("导入单个 .tmn 文件")
                    }
                }
                .disabled(isExporting || isImporting)
            } footer: {
                Text(".tmn 是 Notiee 及关联应用专属的结构化导出格式，支持图文完整记录的无损迁移。")
            }
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExportShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importRecords(from: url)
            case .failure(let error):
                print("Import picker failed: \(error)")
            }
        }
        .sheet(isPresented: $showingImportPreview) {
            BackupImportPreviewSheet(previewData: importPreviewData, store: store)
        }
        .fileImporter(
            isPresented: $showingSingleTMNPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        let (record, todos) = try await TMNImportService.importTMN(url: url)
                        await MainActor.run {
                            self.singleTMNPreview = PreviewData(record: record, todos: todos)
                        }
                    } catch {
                        print("Single TMN import failed: \(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                print("Single TMN import picker failed: \(error)")
            }
        }
        .sheet(item: $singleTMNPreview) { data in
            TMNImportPreviewSheet(record: data.record, todos: data.todos, store: store)
        }
    }
    
    private func exportAllRecords() {
        guard !store.records.isEmpty else { return }
        isExporting = true
        
        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                // Export each record to a .tmn file in the temp directory
                for record in store.records {
                    let tmnURL = try await TMNExportService.export(record: record, store: store)
                    let destURL = tempDir.appendingPathComponent(tmnURL.lastPathComponent)
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: tmnURL, to: destURL)
                }
                
                // Zip the entire temp directory
                let iso8601 = ISO8601DateFormatter()
                let dateStr = iso8601.string(from: Date()).replacingOccurrences(of: ":", with: "-")
                let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("Notiee_Backup_\(dateStr).zip")
                
                if FileManager.default.fileExists(atPath: zipURL.path) {
                    try FileManager.default.removeItem(at: zipURL)
                }
                
                try FileManager.default.zipItem(at: tempDir, to: zipURL)
                
                await MainActor.run {
                    self.exportURL = zipURL
                    self.isExporting = false
                    self.showingExportShareSheet = true
                }
            } catch {
                print("Export failed: \(error)")
                await MainActor.run { self.isExporting = false }
            }
        }
    }
    
    private func importRecords(from zipURL: URL) {
        isImporting = true
        
        Task {
            do {
                guard zipURL.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "BackupRestoreView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot access zip file"])
                }
                defer { zipURL.stopAccessingSecurityScopedResource() }
                
                let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
                
                try FileManager.default.unzipItem(at: zipURL, to: extractDir)
                
                let fileManager = FileManager.default
                let enumerator = fileManager.enumerator(at: extractDir, includingPropertiesForKeys: nil)
                
                var tmnURLs: [URL] = []
                while let fileURL = enumerator?.nextObject() as? URL {
                    if fileURL.pathExtension == "tmn" {
                        tmnURLs.append(fileURL)
                    }
                }
                
                var parsedData: [PreviewData] = []
                for tmnURL in tmnURLs {
                    do {
                        let (record, todos) = try await TMNImportService.importTMN(url: tmnURL)
                        parsedData.append(PreviewData(record: record, todos: todos))
                    } catch {
                        print("Failed to parse \(tmnURL): \(error)")
                    }
                }
                
                await MainActor.run {
                    self.importPreviewData = parsedData
                    self.isImporting = false
                    if !parsedData.isEmpty {
                        self.showingImportPreview = true
                    }
                }
            } catch {
                print("Import failed: \(error)")
                await MainActor.run { self.isImporting = false }
            }
        }
    }
}

struct BackupImportPreviewSheet: View {
    @Environment(\.dismiss) var dismiss
    let previewData: [PreviewData]
    let store: NotieeStore
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("共解析到 \(previewData.count) 条记录。点击确认恢复将它们统一保存至日期导入记录文件夹中。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Section("记录预览") {
                    ForEach(previewData) { data in
                        NavigationLink {
                            TMNImportPreviewSheet(record: data.record, todos: data.todos, store: store)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(data.record.title)
                                    .font(.headline)
                                Text(data.record.summary.isEmpty ? "无摘要" : data.record.summary)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
            .navigationTitle("恢复记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认恢复") {
                        importAll()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func importAll() {
        let folderId = store.createImportedFolder()
        
        for data in previewData {
            let newRecord = NoteRecord(
                id: UUID(),
                eventID: nil,
                folderID: folderId,
                capturedAt: data.record.capturedAt,
                localImagePaths: data.record.localImagePaths,
                title: data.record.title,
                ocrText: data.record.ocrText,
                summary: data.record.summary,
                detailedContent: data.record.detailedContent,
                processingState: data.record.processingState,
                keyPoints: data.record.keyPoints,
                definitions: data.record.definitions,
                isFavorite: data.record.isFavorite,
                isDeleted: data.record.isDeleted,
                editedAt: data.record.editedAt,
                modelsUsed: data.record.modelsUsed,
                tokenUsage: data.record.tokenUsage,
                deviceName: data.record.deviceName
            )
            store.addRecord(newRecord)
            
            for todo in data.todos {
                let newTodo = NoteTodo(
                    id: UUID(),
                    recordID: newRecord.id,
                    content: todo.content,
                    isCompleted: todo.isCompleted,
                    createdAt: todo.createdAt,
                    dueDate: todo.dueDate,
                    hasReminder: todo.hasReminder
                )
                store.addTodo(newTodo)
            }
        }
    }
}

// Ensure ShareSheet exists or create one if not
struct ShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
