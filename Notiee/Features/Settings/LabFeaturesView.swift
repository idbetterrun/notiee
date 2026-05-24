import SwiftUI

struct LabFeaturesView: View {
    @ObservedObject var store: NotieeStore
    @StateObject private var iCloudService = ICloudSyncService.shared
    @State private var showingDocumentPicker = false
    @State private var previewData: PreviewData?
    @State private var syncResultMessage: String?
    
    @AppStorage("labMarkdownRenderingEnabled") private var markdownRenderingEnabled = false
    @AppStorage("notiee.studentMode") private var studentModeEnabled = false
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.purple)
                        .padding(.top, 8)
                    
                    Text("实验室功能")
                        .font(.headline)
                    
                    Text("这里是实验性质的功能，后续可能会删除，也可能会保留，请务必不要过多依赖。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            Section {
                Toggle(isOn: $markdownRenderingEnabled) {
                    Label("Markdown 渲染", systemImage: "m.square")
                }
            } footer: {
                Text("开启后，记录详情页若包含 Markdown 语法，将渲染为样式化排版。")
            }
            
            Section {
                Toggle(isOn: $studentModeEnabled) {
                    Label("学生模式", systemImage: "graduationcap.fill")
                }
            } footer: {
                Text("专为学生群体设计的功能模式。")
            }
            
            Section {
                Button {
                    showingDocumentPicker = true
                } label: {
                    HStack {
                        Label("导入 .tmn 文件", systemImage: "square.and.arrow.down")
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            } footer: {
                Text(".tmn 文件是 Notiee 及关联应用专属的结构化导出格式，支持包含图文等完整记录内容的无损备份与迁移。")
            }
            
            Section {
                if iCloudService.isAvailable() {
                    HStack {
                        Label("iCloud 同步", systemImage: "icloud.and.arrow.up")
                        Spacer()
                        if let date = iCloudService.lastSyncDate {
                            Text("上次同步：" + date.formatted(.relative(presentation: .numeric)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let message = syncResultMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(message.hasPrefix("✓") ? .green : .red)
                            .padding(.vertical, 4)
                    }

                    Button {
                        syncResultMessage = nil
                        Task {
                            do {
                                let count = try await iCloudService.uploadAllRecords(store: store)
                                syncResultMessage = "✓ 成功上传 \(count) 条记录"
                            } catch {
                                syncResultMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack {
                            if iCloudService.isSyncing {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text("上传同步")
                            Spacer()
                            Image(systemName: "arrow.up.doc.fill")
                        }
                    }
                    .disabled(iCloudService.isSyncing)

                    Button {
                        syncResultMessage = nil
                        Task {
                            do {
                                let count = try await iCloudService.downloadAndMerge(store: store)
                                syncResultMessage = "✓ 成功下载合并 \(count) 条记录"
                            } catch {
                                syncResultMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        HStack {
                            if iCloudService.isSyncing {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text("下载同步")
                            Spacer()
                            Image(systemName: "arrow.down.doc.fill")
                        }
                    }
                    .disabled(iCloudService.isSyncing)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("iCloud 同步不可用", systemImage: "icloud.slash")
                            Spacer()
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                        
                        Text("需要 Apple Developer Program 付费账号（$99/年）才能使用 iCloud 同步。请改用「备份与恢复」页面通过 AirDrop 在设备间传输。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("通过 iCloud Drive 在设备间同步记录。使用 UUID 去重，editedAt 版本比较解决冲突。")
            }
        }
        .navigationTitle("实验室")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingDocumentPicker,
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
                            self.previewData = PreviewData(record: record, todos: todos)
                        }
                    } catch {
                        print("Import failed: \(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                print("Import failed: \(error.localizedDescription)")
            }
        }
        .sheet(item: $previewData) { data in
            TMNImportPreviewSheet(record: data.record, todos: data.todos, store: store)
        }
    }
}

struct PreviewData: Identifiable {
    let id = UUID()
    let record: NoteRecord
    let todos: [NoteTodo]
}
