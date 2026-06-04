import SwiftUI

struct AIFeatureSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Text("控制大模型处理拍记时生成哪些类型的内容。关闭某项可减少 Token 消耗。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("摘要 (较低消耗)", isOn: $viewModel.aiEnableSummary)
                Toggle("详细内容 (极高消耗)", isOn: $viewModel.aiEnableDetailedContent)
                Toggle("待办事项 (较低消耗)", isOn: $viewModel.aiEnableTodos)
            }
        }
        .navigationTitle("大模型功能")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.aiEnableSummary) { _, _ in viewModel.saveAll() }
        .onChange(of: viewModel.aiEnableDetailedContent) { _, _ in viewModel.saveAll() }
        .onChange(of: viewModel.aiEnableTodos) { _, _ in viewModel.saveAll() }
    }
}
