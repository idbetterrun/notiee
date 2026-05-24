import Combine
import Foundation
import UIKit

enum CaptureMode {
    case single
    case batch
}

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var capturedRecords: [NoteRecord] = []
    
    @Published var captureMode: CaptureMode = .single
    @Published var batchImagePaths: [String] = []
    
    let cameraManager = CameraManager()

    let currentDate: Date
    private let calendar: Calendar
    private let scheduleMatcher: ScheduleMatcher
    let store: NotieeStore?
    
    @Published var selectedEventID: UUID?
    
    var events: [ScheduledEvent] {
        store?.events ?? []
    }
    
    private var cancellables: Set<AnyCancellable> = []

    init(
        currentDate: Date = Date(),
        calendar: Calendar = .current,
        scheduleMatcher: ScheduleMatcher = ScheduleMatcher()
    ) {
        self.currentDate = currentDate
        self.calendar = calendar
        self.scheduleMatcher = scheduleMatcher
        self.store = nil
        
        setupBindings()
    }

    init(store: NotieeStore) {
        self.currentDate = store.currentDate
        self.calendar = .current
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
            
        cameraManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var currentEvent: ScheduledEvent? {
        if let id = selectedEventID, let event = events.first(where: { $0.id == id }) {
            return event
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
        store?.records.max(by: { $0.capturedAt < $1.capturedAt })
    }

    func onAppear() {
        cameraManager.checkPermissionsAndConfigure()
    }

    func onDisappear() {
        cameraManager.stopSession()
    }

    func capturePhoto() {
        cameraManager.capturePhoto()
    }

    @discardableResult
    func capturePhoto(localImagePath: String) -> NoteRecord {
        let record = NoteRecord(
            eventID: currentEvent?.id,
            capturedAt: currentDate,
            localImagePaths: [localImagePath],
            title: currentEvent.map { "\($0.title) 拍记" } ?? "未分类拍记",
            processingState: .pending
        )
        capturedRecords.insert(record, at: 0)
        return record
    }

    func importPhoto(_ image: UIImage) {
        handleCapturedImage(image)
    }

    private func handleCapturedImage(_ image: UIImage) {
        do {
            let relativePath = try LocalImageStore.shared.saveImage(image)
            
            if captureMode == .batch {
                batchImagePaths.append(relativePath)
                if batchImagePaths.count == 9 {
                    finishBatch()
                }
            } else {
                if let store {
                    let record = store.capturePhoto(localImagePaths: [relativePath])
                    if !store.autoProcessAfterCapture {
                        store.processRecord(record)
                    }
                } else {
                    let record = NoteRecord(
                        eventID: currentEvent?.id,
                        capturedAt: currentDate,
                        localImagePaths: [relativePath],
                        title: currentEvent.map { "\($0.title) 拍记" } ?? "未分类拍记",
                        processingState: .pending
                    )
                    capturedRecords.insert(record, at: 0)
                }
            }
        } catch {
            print("Failed to save captured image: \(error)")
        }
    }

    func finishBatch() {
        guard !batchImagePaths.isEmpty else { return }
        if let store {
            let record = store.capturePhoto(localImagePaths: batchImagePaths)
            if !store.autoProcessAfterCapture {
                store.processRecord(record)
            }
        } else {
            let record = NoteRecord(
                eventID: currentEvent?.id,
                capturedAt: currentDate,
                localImagePaths: batchImagePaths,
                title: currentEvent.map { "\($0.title) 连拍" } ?? "未分类连拍",
                processingState: .pending
            )
            capturedRecords.insert(record, at: 0)
        }
        batchImagePaths.removeAll()
    }

    static func sample(currentDate: Date = Date()) -> CaptureViewModel {
        let currentDate = Date()
        return CaptureViewModel(currentDate: currentDate)
    }
}
