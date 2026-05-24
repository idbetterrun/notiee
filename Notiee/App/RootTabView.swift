import SwiftUI

struct RootTabView: View {
    @StateObject private var store: NotieeStore
    @State private var selectedTab: AppTab

    @State private var previewData: PreviewData?
    private let settingsStore: AppSettingsPersisting

    @MainActor
    init(
        store: NotieeStore? = nil,
        settingsStore: AppSettingsPersisting = UserDefaultsAppSettingsStore.live
    ) {
        _store = StateObject(wrappedValue: store ?? NotieeStore.live(settingsStore: settingsStore))
        _selectedTab = State(initialValue: settingsStore.loadDefaultTab())
        self.settingsStore = settingsStore
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(store: store)
                .tabItem {
                    Label(AppTab.today.titleKey, systemImage: AppTab.today.systemImage)
                }
                .tag(AppTab.today)

            CaptureView(viewModel: CaptureViewModel(store: store))
                .tabItem {
                    Label(AppTab.capture.titleKey, systemImage: AppTab.capture.systemImage)
                }
                .tag(AppTab.capture)

            RecordsView(store: store)
                .tabItem {
                    Label(AppTab.records.titleKey, systemImage: AppTab.records.systemImage)
                }
                .tag(AppTab.records)

            MeView(settingsStore: settingsStore, store: store)
                .tabItem {
                    Label(AppTab.settings.titleKey, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
        }
        .onAppear {
            store.syncCalendar()
        }
        .onOpenURL { url in
            guard url.pathExtension == "tmn" else { return }
            
            Task {
                do {
                    let (record, todos) = try await TMNImportService.importTMN(url: url)
                    await MainActor.run {
                        self.previewData = PreviewData(record: record, todos: todos)
                    }
                } catch {
                    print("Import failed from URL: \(error.localizedDescription)")
                }
            }
        }
        .sheet(item: $previewData) { data in
            TMNImportPreviewSheet(record: data.record, todos: data.todos, store: store)
        }
    }
}
