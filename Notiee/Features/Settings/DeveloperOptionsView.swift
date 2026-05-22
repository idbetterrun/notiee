import SwiftUI

struct DeveloperOptionsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    
    var body: some View {
        Form {
            Section(header: Text("说明"), footer: Text("配置后，需在常规设置页的“选择供应商”中选择“自定义模型”以启用。")) {
                Text("在此处添加与 OpenAI 或 Anthropic API 兼容的自定义端点。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            
            NavigationLink {
                CustomAIConfigurationView(viewModel: viewModel, kind: .text)
            } label: {
                Text("配置自定义文本模型")
            }
            
            NavigationLink {
                CustomAIConfigurationView(viewModel: viewModel, kind: .vision)
            } label: {
                Text("配置自定义视觉模型")
            }
        }
        .navigationTitle("开发者选项")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CustomAIConfigurationView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let kind: AIModelKind
    
    var body: some View {
        Form {
            Section("自定义模型配置") {
                Picker("API 协议", selection: configuration.customProtocol) {
                    ForEach(AIProtocol.allCases) { proto in
                        Text(proto.displayName).tag(proto)
                    }
                }
                
                TextField("接口地址 (Base URL)", text: configuration.customEndpoint)
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
                Button("保存并启用") {
                    configuration.wrappedValue.providerType = .custom
                    switch kind {
                    case .text:
                        viewModel.saveTextConfiguration()
                    case .vision:
                        viewModel.saveVisionConfiguration()
                    }
                }
            }
        }
        .navigationTitle(kind == .text ? "自定义文本" : "自定义视觉")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var configuration: Binding<AIModelConfiguration> {
        switch kind {
        case .text:
            return $viewModel.textConfiguration
        case .vision:
            return $viewModel.visionConfiguration
        }
    }
}
