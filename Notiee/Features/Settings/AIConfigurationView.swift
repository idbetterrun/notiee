import SwiftUI
import Charts


// MARK: - AIConfigurationView
struct AIConfigurationView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let kind: AIModelKind

    var body: some View {
        Form {
            if configuration.wrappedValue.providerType == .custom {
                Section {
                    Text("当前正在使用自定义大模型，请前往“高级设置 -> 管理自定义模型”中修改配置。如果要换回内置服务商，请在下方重新选择。")
                        .foregroundStyle(.orange)
                }
            }
            
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

            if configuration.wrappedValue.providerType != .custom {
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
                }
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

// MARK: - Components
struct AIConfigurationRow: View {
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

struct ConnectionStatusView: View {
    let status: AIConnectionTestStatus

    var body: some View {
        switch status {
        case .idle:
            Text("点击“测试连接”验证配置是否可用。")
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
                .textSelection(.enabled)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }
}

