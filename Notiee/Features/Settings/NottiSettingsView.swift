import SwiftUI

struct NottiSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    NottiStyleSettingsView()
                } label: {
                    Label("聊天风格", systemImage: "theatermasks")
                }

                NavigationLink {
                    NottiMemoryView()
                } label: {
                    Label("记忆", systemImage: "brain.head.profile")
                }

                NavigationLink {
                    AgentSettingsView(viewModel: viewModel)
                } label: {
                    Label("Agent 设置", systemImage: "bolt.fill")
                }
            }
        }
        .navigationTitle("Notti")
        .navigationBarTitleDisplayMode(.inline)
    }
}
