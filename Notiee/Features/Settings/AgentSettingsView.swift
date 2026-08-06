import SwiftUI

struct AgentSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            if !NottiTierLimits.isAgentAllowed {
                Section {
                    Label("Agent 模式为 Pro 会员专属", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            }

            Section {
                Text("Agent 模式可在 Notti 对话界面随时手动开关。以下设置控制 Agent 执行时的行为。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("信任级别", selection: $viewModel.agentTrustLevel) {
                    Text("谨慎").tag("cautious")
                    Text("标准").tag("standard")
                    Text("完全信任").tag("full")
                }
                Stepper("回路最大轮数: \(viewModel.agentMaxIterations)", value: $viewModel.agentMaxIterations, in: 1...10)
                Stepper("单轮工具上限: \(viewModel.agentMaxToolsPerRound)", value: $viewModel.agentMaxToolsPerRound, in: 1...5)
            }

            // BYOK only: on the free build the Bocha key lives server-side, so
            // users never enter it here. web_search there routes through the backend.
            #if NOTIEE_PLUS
            Section {
                SecureField("博查搜索 API Key", text: $viewModel.bochaSearchAPIKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("联网搜索")
            } footer: {
                Text("填写后 Agent 可联网搜索实时信息（新闻、赛果、天气等）。使用博查（bochaai.com）搜索服务，需自行申请 API Key，按调用量计费。留空则关闭联网搜索。")
            }
            #endif
        }
        .navigationTitle("Agent 设置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.agentTrustLevel) { _, _ in viewModel.saveAll() }
        .onChange(of: viewModel.agentMaxIterations) { _, _ in viewModel.saveAll() }
        .onChange(of: viewModel.agentMaxToolsPerRound) { _, _ in viewModel.saveAll() }
        #if NOTIEE_PLUS
        .onChange(of: viewModel.bochaSearchAPIKey) { _, _ in viewModel.saveAll() }
        #endif
    }
}
