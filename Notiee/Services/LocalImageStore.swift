import UIKit
import Foundation

@MainActor
final class LocalImageStore {
    static let shared = LocalImageStore()

    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var imagesDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("CapturedImages", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private init() {}

    /// Saves an image to the local documents directory and returns the relative path.
    func saveImage(_ image: UIImage) throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "LocalImageStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to JPEG data"])
        }

        let filename = UUID().uuidString + ".jpg"
        let fileURL = imagesDirectory.appendingPathComponent(filename)

        try data.write(to: fileURL)
        return "CapturedImages/\(filename)"
    }

    /// Loads an image from the given relative path.
    func loadImage(path: String) -> UIImage? {
        if path.hasPrefix("mock://") {
            // Future mock handling or fallback
            return nil
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(path)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return UIImage(data: data)
    }
}
