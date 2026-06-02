import SwiftUI
import Charts


// MARK: - CustomModelsListView
struct CustomModelsListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showingAddSheet = false
    @State private var editingModel: CustomAIModel?

    var body: some View {
        List {
            if viewModel.customModels.isEmpty {
                Section {
                    Text("暂无自定义模型，点击下方按钮添加。")
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(viewModel.customModels) { model in
                    Button {
                        editingModel = model
                        showingAddSheet = true
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                HStack {
                                    Text(model.kind.title)
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor.opacity(0.1))
                                        .foregroundColor(.accentColor)
                                        .cornerRadius(4)
                                    
                                    Text(model.protocolType.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.footnote)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteModels)
            }
        }
        .navigationTitle("管理自定义模型")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    editingModel = nil
                    showingAddSheet = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            CustomModelEditSheet(
                model: editingModel,
                onSave: { newModel in
                    if let index = viewModel.customModels.firstIndex(where: { $0.id == newModel.id }) {
                        viewModel.customModels[index] = newModel
                    } else {
                        viewModel.customModels.append(newModel)
                    }
                    viewModel.saveAll()
                }
            )
        }
    }
    
    private func deleteModels(at offsets: IndexSet) {
        viewModel.customModels.remove(atOffsets: offsets)
        viewModel.saveAll()
    }
}

struct CustomModelEditSheet: View {
    @Environment(\.dismiss) var dismiss
    
    let model: CustomAIModel?
    let onSave: (CustomAIModel) -> Void
    
    @State private var name: String = ""
    @State private var kind: AIModelKind = .text
    @State private var protocolType: AIProtocol = .openai
    @State private var endpoint: String = ""
    @State private var modelIdentifier: String = ""
    @State private var apiKey: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("名称 (如: 我的本地 Qwen)", text: $name)
                    Picker("类型", selection: $kind) {
                        Text(AIModelKind.text.title).tag(AIModelKind.text)
                        Text(AIModelKind.vision.title).tag(AIModelKind.vision)
                    }
                    Picker("协议", selection: $protocolType) {
                        Text("OpenAI").tag(AIProtocol.openai)
                        Text("Anthropic").tag(AIProtocol.anthropic)
                    }
                }
                
                Section("连接配置") {
                    TextField("Endpoint (如: https://api.openai.com/v1/chat/completions)", text: $endpoint)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    TextField("Model ID (如: gpt-4o)", text: $modelIdentifier)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    SecureField("API Key", text: $apiKey)
                }
            }
            .navigationTitle(model == nil ? "添加模型" : "编辑模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let newModel = CustomAIModel(
                            id: model?.id ?? UUID(),
                            name: name.isEmpty ? "未命名模型" : name,
                            kind: kind,
                            endpoint: endpoint,
                            protocolType: protocolType,
                            modelIdentifier: modelIdentifier,
                            apiKey: apiKey
                        )
                        onSave(newModel)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let model = model {
                    name = model.name
                    kind = model.kind
                    protocolType = model.protocolType
                    endpoint = model.endpoint
                    modelIdentifier = model.modelIdentifier
                    apiKey = model.apiKey
                }
            }
        }
    }
}

