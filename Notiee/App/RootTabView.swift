import SwiftUI

struct RootTabView: View {
    @StateObject private var store: NotieeStore
    @State private var selectedTab: AppTab

    private let settingsStore: AppSettingsPersisting

    @MainActor
    init(
        store: NotieeStore? = nil,
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live
    ) {
        _store = StateObject(wrappedValue: store ?? NotieeStore.live())
        _selectedTab = State(initialValue: settingsStore.loadDefaultTab())
        self.settingsStore = settingsStore
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(store: store)
                .tabItem {
                    Label(AppTab.today.title, systemImage: AppTab.today.systemImage)
                }
                .tag(AppTab.today)

            CaptureView(viewModel: CaptureViewModel(store: store))
                .tabItem {
                    Label(AppTab.capture.title, systemImage: AppTab.capture.systemImage)
                }
                .tag(AppTab.capture)

            RecordsView(store: store)
                .tabItem {
                    Label(AppTab.records.title, systemImage: AppTab.records.systemImage)
                }
                .tag(AppTab.records)

            SettingsView(settingsStore: settingsStore)
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
        }
    }
}
