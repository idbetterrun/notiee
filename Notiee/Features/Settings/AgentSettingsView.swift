import SwiftUI

struct AgentSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Text("Agent 模式可在 Spark 对话界面随时手动开关。以下设置控制 Agent 执行时的行为。")
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
        }
        .navigationTitle("Agent 设置")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.agentTrustLevel) { _, _ in viewModel.saveAll() }
        .onChange(of: viewModel.agentMaxIterations) { _, _ in viewModel.saveAll() }
        .onChange(of: viewModel.agentMaxToolsPerRound) { _, _ in viewModel.saveAll() }
    }
}
