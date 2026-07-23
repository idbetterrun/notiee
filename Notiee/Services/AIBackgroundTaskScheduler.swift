import BackgroundTasks

@MainActor
protocol AIProcessingScheduling: AnyObject {
    func register(handler: @escaping () async -> Void)
    func scheduleProcessing()
}

@MainActor
final class AIBackgroundTaskScheduler: AIProcessingScheduling {
    static let shared = AIBackgroundTaskScheduler()
    static let identifier = "com.idbetterrun.notiee.ai-processing"

    private var registeredHandler: (() async -> Void)?

    private init() {}

    func register(handler: @escaping () async -> Void) {
        registeredHandler = handler
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            let childTask = Task {
                await handler()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                childTask.cancel()
            }
        }
    }

    func scheduleProcessing() {
        let request = BGProcessingTaskRequest(identifier: Self.identifier)
        request.requiresNetworkConnectivity = true
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch let error as NSError where error.code == 1 && error.domain == "BGTaskSchedulerErrorDomain" {
            // Duplicate submission — already scheduled.
        } catch {
            Logger.general.error("BGTaskScheduler submit failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
