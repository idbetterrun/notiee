import XCTest
import UIKit
@testable import Notiee

@MainActor
final class LocalImageStoreDeleteTests: XCTestCase {
    func testDeleteImage_removesFileSavedByStore() throws {
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        let relPath = try LocalImageStore.shared.saveImage(image)
        XCTAssertNotNil(LocalImageStore.readImageData(path: relPath))

        LocalImageStore.deleteImage(path: relPath)

        XCTAssertNil(LocalImageStore.readImageData(path: relPath),
                     "delete should resolve path relative to Documents and actually remove the file")
    }

    func testDeleteImage_mockPathIsNoop() {
        LocalImageStore.deleteImage(path: "mock://placeholder")
    }
}
