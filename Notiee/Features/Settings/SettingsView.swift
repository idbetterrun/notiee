import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    @MainActor
    init(settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(settingsStore: settingsStore))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("启动偏好") {
                    Picker("默认页面", selection: $viewModel.defaultTab) {
                        ForEach(AppTab.launchCandidates) { tab in
                            Label(tab.title, systemImage: tab.systemImage)
                                .tag(tab)
                        }
                    }
                    .onChange(of: viewModel.defaultTab) { _, _ in
                        viewModel.saveDefaultTab()
                    }
                }

                Section("AI API") {
                    NavigationLink {
                        AIConfigurationView(viewModel: viewModel, kind: .text)
                    } label: {
                        AIConfigurationRow(
                            title: AIModelKind.text.title,
                            systemImage: "text.bubble",
                            configuration: viewModel.textConfiguration
                        )
                    }

                    NavigationLink {
                        AIConfigurationView(viewModel: viewModel, kind: .vision)
                    } label: {
                        AIConfigurationRow(
                            title: AIModelKind.vision.title,
                            systemImage: "eye",
                            configuration: viewModel.visionConfiguration
                        )
                    }

                    if let lastSaveError = viewModel.lastSaveError {
                        Label(lastSaveError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("高级设置") {
                    NavigationLink {
                        DeveloperOptionsView(viewModel: viewModel)
                    } label: {
                        Label("开发者选项", systemImage: "hammer")
                    }
                }
                
                Section("安全与隐私") {
                    Text("API Key 将加密保存在本机 Keychain，不写入普通偏好存储。")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("我")
        }
    }
}

#Preview {
    SettingsView()
}

private struct AIConfigurationRow: View {
    let title: String
    let systemImage: String
    let configuration: AIModelConfiguration

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(configuration.isComplete ? .green : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)

                Text(configuration.isComplete ? configuration.modelName : "未配置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AIConfigurationView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let kind: AIModelKind

    var body: some View {
        Form {
            Section("服务商") {
                Picker("选择供应商", selection: configuration.providerType) {
                    ForEach(AIProviderType.allCases.filter { supports(provider: $0, for: kind) }) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: configuration.wrappedValue.providerType) { _ in
                    let currentProvider = configuration.wrappedValue.providerType
                    if let firstModel = currentProvider.predefinedModels.first {
                        configuration.wrappedValue.modelName = firstModel
                    } else {
                        configuration.wrappedValue.modelName = ""
                    }
                }
                

            }

            Section("模型设置") {
                let currentProvider = configuration.wrappedValue.providerType
                if !currentProvider.predefinedModels.isEmpty {
                    Picker("模型名称", selection: configuration.modelName) {
                        ForEach(currentProvider.predefinedModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                } else {
                    TextField(currentProvider.isEndpointIdRequired ? "接入点 ID (ep-xxxxxx)" : "模型名称", text: configuration.modelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                
                SecureField("API Key", text: configuration.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if configuration.wrappedValue.providerType.isEndpointIdRequired {
                Section {
                    Text("火山方舟要求传入您创建的专属接入点 ID (Endpoint ID，以 ep- 开头)，而不是模型原始名称。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("保存配置") {
                    saveConfiguration()
                }

                Button("测试连接") {
                    viewModel.testConnection(for: kind)
                }
            }

            Section("连接状态") {
                ConnectionStatusView(status: viewModel.connectionTestStatus)
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var configuration: Binding<AIModelConfiguration> {
        switch kind {
        case .text:
            $viewModel.textConfiguration
        case .vision:
            $viewModel.visionConfiguration
        }
    }
    
    private func supports(provider: AIProviderType, for kind: AIModelKind) -> Bool {
        if provider == .custom { return true }
        switch kind {
        case .text:
            return [.qwenText, .doubaoText, .deepseek, .minimax].contains(provider)
        case .vision:
            return [.qwenVision, .doubaoVision].contains(provider)
        }
    }

    private func saveConfiguration() {
        switch kind {
        case .text:
            viewModel.saveTextConfiguration()
        case .vision:
            viewModel.saveVisionConfiguration()
        }
    }
}

private struct ConnectionStatusView: View {
    let status: AIConnectionTestStatus

    var body: some View {
        switch status {
        case .idle:
            Text("点击“连接测试”验证配置是否可用。")
                .foregroundStyle(.secondary)
        case .testing:
            HStack(spacing: 8) {
                ProgressView()
                Text("正在连接 API 并发送测试请求...")
                    .foregroundStyle(.secondary)
            }
        case .success(let message):
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}
