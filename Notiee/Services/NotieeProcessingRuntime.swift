import Foundation

@MainActor
final class NotieeProcessingRuntime {
    static let shared = NotieeProcessingRuntime(store: .live(), scheduler: AIBackgroundTaskScheduler.shared)

    let store: NotieeStore
    private let scheduler: any AIProcessingScheduling

    init(
        store: NotieeStore,
        scheduler: any AIProcessingScheduling
    ) {
        self.store = store
        self.scheduler = scheduler
    }

    func scheduleProcessing() {
        scheduler.register { [weak self] in
            await self?.runPendingProcessing()
        }
        scheduler.scheduleProcessing()
    }
    func runPendingProcessing() async { await store.resumePendingAIProcessing() }
}
