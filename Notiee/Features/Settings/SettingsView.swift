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
            Section("服务") {
                TextField("供应商名称", text: configuration.providerName)
                    .textInputAutocapitalization(.never)

                TextField("接口地址", text: configuration.endpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("模型名称", text: configuration.modelName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField("API Key", text: configuration.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
            Text("保存配置后可在本机校验字段完整性。")
                .foregroundStyle(.secondary)
        case .success(let message):
            Label(message, systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}
