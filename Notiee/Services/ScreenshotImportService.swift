import Foundation
import UIKit

enum ScreenshotImportError: LocalizedError {
    case missingImage
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .missingImage: String(localized: "未提供截图")
        case .invalidImage: String(localized: "截图格式无效")
        }
    }
}

@MainActor
struct ScreenshotImportService {
    let store: NotieeStore
    let imageSaver: any ImageSaving
    let scheduler: any AIProcessingScheduling

    func importScreenshotData(_ data: Data) throws -> UUID {
        guard let image = UIImage(data: data) else {
            throw ScreenshotImportError.invalidImage
        }
        let imagePath = try imageSaver.saveImage(image)
        let record = store.captureShortcutScreenshot(localImagePath: imagePath)
        scheduler.scheduleProcessing()
        store.processImportedScreenshot(recordID: record.id)
        return record.id
    }
}
