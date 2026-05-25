import SwiftUI

struct LabFeaturesView: View {
    @ObservedObject var store: NotieeStore
    @StateObject private var iCloudService = ICloudSyncService.shared
    @State private var showingDocumentPicker = false
    @State private var previewData: PreviewData?
    @State private var syncResultMessage: String?
    
    @AppStorage("labMarkdownRenderingEnabled") private var markdownRenderingEnabled = false
    @AppStorage("notiee.studentMode") private var studentModeEnabled = false
    @AppStorage("labFullVisionModeEnabled") private var fullVisionModeEnabled = false
    @AppStorage("labDeepAssociationModeEnabled") private var deepAssociationModeEnabled = false
    
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
                HStack {
                    Toggle(isOn: $fullVisionModeEnabled) {
                        HStack(spacing: 6) {
                            Label("全功能视觉模式", systemImage: "eye.fill")
                            Text("Beta")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.gradient, in: Capsule())
                        }
                    }
                }
            } footer: {
                Text("开启后视觉模型将对图片进行全方位描述，包括文字和非文字信息（如物体、场景、图表等），而非仅进行 OCR 提取。")
            }

            Section {
                Toggle(isOn: $deepAssociationModeEnabled) {
                    Label("深度联想模式", systemImage: "brain.head.profile.fill")
                }
                .disabled(true)
            } footer: {
                Text("对记录的文本内容进行深度语义联想，自动关联知识图谱和上下文。该功能尚未开放，敬请期待。")
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
                            Text(date.formatted(.relative(presentation: .numeric)))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Menu {
                            Button {
                                syncResultMessage = nil
                                Task {
                                    do {
                                        let count = try await iCloudService.uploadAllRecords(store: store)
                                        syncResultMessage = "✓ 已上传 \(count) 条记录"
                                    } catch {
                                        syncResultMessage = error.localizedDescription
                                    }
                                }
                            } label: {
                                Label("上传同步", systemImage: "arrow.up.doc.fill")
                            }
                            Button {
                                syncResultMessage = nil
                                Task {
                                    do {
                                        let count = try await iCloudService.downloadAndMerge(store: store)
                                        syncResultMessage = "✓ 已下载合并 \(count) 条记录"
                                    } catch {
                                        syncResultMessage = error.localizedDescription
                                    }
                                }
                            } label: {
                                Label("下载同步", systemImage: "arrow.down.doc.fill")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .foregroundColor(.blue)
                        }
                        .disabled(iCloudService.isSyncing)
                    }

                    if iCloudService.isSyncing {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 6)
                            Text("同步中...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let message = syncResultMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(message.hasPrefix("✓") ? .green : .red)
                    }
                } else {
                    HStack {
                        Label("iCloud 同步", systemImage: "icloud.slash")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("不可用")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text(iCloudService.isAvailable() ? "通过 iCloud Drive 在设备间同步记录。" : "需要 Apple Developer Program 付费账号才能使用。请改用「备份与恢复」通过 AirDrop 传输。")
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
