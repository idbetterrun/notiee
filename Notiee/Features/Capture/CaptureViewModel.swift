import Combine
import Foundation
import UIKit

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var capturedRecords: [NoteRecord] = []
    
    let cameraManager = CameraManager()

    private let currentDate: Date
    private let events: [ScheduledEvent]
    private let scheduleMatcher: ScheduleMatcher
    private let store: NotieeStore?
    private var cancellables: Set<AnyCancellable> = []

    init(
        currentDate: Date = Date(),
        events: [ScheduledEvent] = [],
        scheduleMatcher: ScheduleMatcher = ScheduleMatcher()
    ) {
        self.currentDate = currentDate
        self.events = events
        self.scheduleMatcher = scheduleMatcher
        self.store = nil
        
        setupBindings()
    }

    init(store: NotieeStore) {
        self.currentDate = store.currentDate
        self.events = store.events
        self.scheduleMatcher = ScheduleMatcher()
        self.store = store
        
        setupBindings()
    }
    
    private func setupBindings() {
        cameraManager.$capturedImage
            .compactMap { $0 }
            .sink { [weak self] image in
                self?.handleCapturedImage(image)
            }
            .store(in: &cancellables)
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

    func onAppear() {
        cameraManager.checkPermissionsAndConfigure()
    }

    func onDisappear() {
        cameraManager.stopSession()
    }

    func capturePhoto() {
        cameraManager.capturePhoto()
        // The actual record creation happens in handleCapturedImage when the camera returns the image
    }

    private func handleCapturedImage(_ image: UIImage) {
        do {
            let relativePath = try LocalImageStore.shared.saveImage(image)
            
            if let store {
                let record = store.capturePhoto(localImagePath: relativePath)
                capturedRecords.insert(record, at: 0)
            } else {
                let event = currentEvent
                let captureIndex = capturedRecords.count + 1
                let record = NoteRecord(
                    eventID: event?.id,
                    capturedAt: currentDate,
                    localImagePath: relativePath,
                    title: event.map { "\($0.title) 拍记" } ?? "未分类拍记",
                    processingState: .pending
                )
                capturedRecords.insert(record, at: 0)
            }
        } catch {
            print("Failed to save captured image: \(error)")
        }
    }

    static func sample(currentDate: Date = Date()) -> CaptureViewModel {
        let today = TodayViewModel.sample(currentDate: currentDate)
        return CaptureViewModel(currentDate: currentDate, events: today.events)
    }
}
