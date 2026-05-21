import Combine
import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var capturedRecords: [NoteRecord] = []

    private let currentDate: Date
    private let events: [ScheduledEvent]
    private let scheduleMatcher: ScheduleMatcher
    private let store: NotieeStore?

    init(
        currentDate: Date = Date(),
        events: [ScheduledEvent] = [],
        scheduleMatcher: ScheduleMatcher = ScheduleMatcher()
    ) {
        self.currentDate = currentDate
        self.events = events
        self.scheduleMatcher = scheduleMatcher
        self.store = nil
    }

    init(store: NotieeStore) {
        self.currentDate = store.currentDate
        self.events = store.events
        self.scheduleMatcher = ScheduleMatcher()
        self.store = store
    }

    var currentEvent: ScheduledEvent? {
        if let store {
            return store.currentEvent
        }

        return scheduleMatcher.currentEvent(from: events, at: currentDate)
    }

    var contextTitle: String {
        currentEvent?.title ?? "未分类"
    }

    var contextSubtitle: String {
        currentEvent == nil ? "当前无日程，照片会进入暂存区" : "照片会自动归入当前日程"
    }

    var latestRecord: NoteRecord? {
        capturedRecords.first
    }

    @discardableResult
    func capturePhoto(localImagePath: String? = nil) -> NoteRecord {
        if let store {
            let record = store.capturePhoto(localImagePath: localImagePath)
            capturedRecords.insert(record, at: 0)
            return record
        }

        let event = currentEvent
        let captureIndex = capturedRecords.count + 1
        let record = NoteRecord(
            eventID: event?.id,
            capturedAt: currentDate,
            localImagePath: localImagePath ?? "mock://capture-\(captureIndex)",
            title: event.map { "\($0.title) 拍记" } ?? "未分类拍记",
            processingState: .pending
        )

        capturedRecords.insert(record, at: 0)
        return record
    }

    static func sample(currentDate: Date = Date()) -> CaptureViewModel {
        let today = TodayViewModel.sample(currentDate: currentDate)
        return CaptureViewModel(currentDate: currentDate, events: today.events)
    }
}
