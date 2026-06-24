import SwiftUI

struct LabFeaturesView: View {
    @ObservedObject var store: NotieeStore
    @StateObject private var iCloudService = ICloudSyncService.shared
    @State private var syncResultMessage: String?
    
    @AppStorage(UDK.labFullVisionModeEnabled) private var fullVisionModeEnabled = false
    @AppStorage(UDK.labDeepAssociationModeEnabled) private var deepAssociationModeEnabled = false
    @AppStorage(UDK.labLowConsumptionModeEnabled) private var lowConsumptionModeEnabled = false
    @AppStorage("spark.semanticSearch.useCloud") private var useCloudEmbedding = false

    @State private var showDeepAssociationDetail = false
    
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "flask.fill")
                        .font(.system(size: 48))
                        .foregroundColor(NotieeColors.themed(.purple))
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
                Toggle(isOn: $lowConsumptionModeEnabled) {
                    Label("低消耗模式", systemImage: "leaf.fill")
                }
            } footer: {
                Text("开启后使用设备端神经网络（Apple Neural Engine）进行文字识别，云端仅做摘要。可节省约 50% Token 消耗，处理速度更快且无需联网 OCR。与全功能视觉模式互斥，开启后自动关闭全功能视觉模式。")
            }
            .onChange(of: lowConsumptionModeEnabled) { _, newValue in
                if newValue { fullVisionModeEnabled = false }
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
                Text("开启后视觉模型将对图片进行全方位描述，包括文字和非文字信息（如物体、场景、图表等），而非仅进行 OCR 提取。「创作者/研究者」场景预设会自动启用此模式。与低消耗模式互斥，开启后自动关闭低消耗模式。")
            }
            .onChange(of: fullVisionModeEnabled) { _, newValue in
                if newValue { lowConsumptionModeEnabled = false }
            }

            Section {
                Toggle(isOn: $deepAssociationModeEnabled) {
                    Label("深度联想模式", systemImage: "brain.head.profile.fill")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("在笔记之间发现隐藏的关联，让 Notiee 帮你串联知识。")
                    Button {
                        withAnimation { showDeepAssociationDetail.toggle() }
                    } label: {
                        Text(showDeepAssociationDetail ? "收起 ▲" : "更多 ▼")
                            .font(.caption)
                            .foregroundColor(NotieeColors.themed(.blue))
                    }
                    if showDeepAssociationDetail {
                        Text("开启后：\n• 笔记续篇检测：同课程相邻时间的笔记自动提示关联\n• 相关内容推荐：详情页底部展示相关历史笔记\n• 后续将支持知识图谱和语义搜索")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            }

            Section("语义检索") {
                Toggle("高质量云端检索", isOn: $useCloudEmbedding)
                Text("默认在本机计算语义向量（离线、不外传）。开启后用你配置的 AI 服务商接口计算，检索更准但会把拍记文本发送到该服务。")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                                .foregroundColor(NotieeColors.themed(.blue))
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
        .featureHint(
            key: "hint_full_vision_seen",
            title: "全功能视觉模式",
            message: "开启后 AI 会全面分析图片中的所有元素，包括物体、场景、图表等。创作者和研究者场景预设会自动启用。",
            icon: "eye.fill"
        )
        .featureHint(
            key: "hint_deep_association_seen", 
            title: "深度联想模式",
            message: "开启后记录详情底部会展示相关历史笔记，帮你发现知识之间的隐藏关联。",
            icon: "brain.head.profile.fill"
        )
    }
}

struct PreviewData: Identifiable {
    let id = UUID()
    let record: NoteRecord
    let todos: [NoteTodo]
}
