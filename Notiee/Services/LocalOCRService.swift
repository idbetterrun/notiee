import Foundation
import Vision
import UIKit

struct LocalOCRService {
    enum RecognitionLevel {
        case fast
        case accurate
    }

    static func recognizeText(from image: UIImage, level: RecognitionLevel = .accurate) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw LocalOCRError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: LocalOCRError.recognitionFailed(error.localizedDescription))
                    return
                }

                let results = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = results.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }

            request.recognitionLevel = level == .accurate ? .accurate : .fast
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: LocalOCRError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    static func batchRecognize(imagePaths: [String]) async throws -> String {
        var results: [String] = []
        for path in imagePaths {
            guard let data = LocalImageStore.readImageData(path: path),
                  let image = UIImage(data: data) else { continue }
            let text = try await recognizeText(from: image)
            if !text.isEmpty {
                results.append(text)
            }
        }
        return results.joined(separator: "\n---\n")
    }
}

enum LocalOCRError: LocalizedError {
    case invalidImage
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取图片数据"
        case .recognitionFailed(let msg): return "本地 OCR 识别失败：\(msg)"
        }
    }
}
