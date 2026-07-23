import XCTest
import UIKit
@testable import Notiee

@MainActor
final class SpyImageSaver: ImageSaving {
    var saveCallCount = 0
    let path: String

    init(path: String) {
        self.path = path
    }

    func saveImage(_ image: UIImage) throws -> String {
        saveCallCount += 1
        return path
    }
}

@MainActor
final class ScreenshotImportServiceTests: XCTestCase {

    func testImport_validImageSavesRecordBeforeScheduling() throws {
        let store = makeStore(records: [])
        let saver = SpyImageSaver(path: "CapturedImages/shortcut.jpg")
        let scheduler = RecordingScheduler()
        let service = ScreenshotImportService(store: store, imageSaver: saver, scheduler: scheduler)

        let recordID = try service.importScreenshotData(makePNGData())

        XCTAssertEqual(saver.saveCallCount, 1)
        XCTAssertEqual(store.record(id: recordID)?.localImagePaths, ["CapturedImages/shortcut.jpg"])
        XCTAssertEqual(store.record(id: recordID)?.processingState, .pending)
        XCTAssertEqual(store.record(id: recordID)?.processingNotificationState, .requested)
        XCTAssertEqual(scheduler.scheduleCallCount, 1)
    }

    func testImport_invalidDataThrowsWithoutCreatingRecord() {
        let store = makeStore(records: [])
        let service = ScreenshotImportService(store: store, imageSaver: SpyImageSaver(path: "unused"), scheduler: RecordingScheduler())

        XCTAssertThrowsError(try service.importScreenshotData(Data("not an image".utf8)))
        XCTAssertTrue(store.records.isEmpty)
    }

    private func makeStore(records: [NoteRecord]) -> NotieeStore {
        NotieeStore(
            currentDate: referenceDate,
            events: [],
            todos: [],
            records: records,
            recordStore: JSONNoteRecordStore(fileURL: temporaryFileURL()),
            aiService: MockAIProcessingService(processingDelay: 0.01...0.02),
            autoProcess: false
        )
    }

    private func makePNGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return image.pngData()!
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    private var referenceDate: Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
        components.year = 2026
        components.month = 5
        components.day = 21
        components.hour = 10
        components.minute = 30
        return components.date!
    }
}
