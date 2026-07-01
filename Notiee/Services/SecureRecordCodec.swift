import Foundation
import UIKit

/// Encrypts / decrypts a single NoteRecord's sensitive payload (text fields + todos)
/// and its image files. The encrypted blob (Data) holds the JSON of the sensitive
/// payload; callers persist it separately (see SecureRecordCodec.blobURL).
@MainActor
struct SecureRecordCodec {
    struct SensitivePayload: Codable {
        var title: String
        var ocrText: String
        var summary: String
        var detailedContent: String
        var keyPoints: [String]
        var definitions: [KeyDefinition]
        var todos: [NoteTodo]
    }

    static let lockedPlaceholderTitle = "🔒 已加密拍记"

    private let crypto: CryptoService
    private let fileManager = FileManager.default

    init(crypto: CryptoService) {
        self.crypto = crypto
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var encryptedDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("EncryptedRecords", isDirectory: true)
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    func blobURL(for recordID: UUID) -> URL {
        encryptedDirectory.appendingPathComponent("\(recordID.uuidString).enc")
    }

    // MARK: - Encrypt

    /// Returns the redacted record (to persist) and the ciphertext blob (to write to disk).
    func encrypt(record: NoteRecord, todos: [NoteTodo]) throws -> (record: NoteRecord, blob: Data) {
        let payload = SensitivePayload(
            title: record.title,
            ocrText: record.ocrText,
            summary: record.summary,
            detailedContent: record.detailedContent,
            keyPoints: record.keyPoints,
            definitions: record.definitions,
            todos: todos
        )
        let blob = try crypto.encrypt(try JSONEncoder().encode(payload))

        // Encrypt image files: write "<path>.enc" first, then delete the plaintext.
        var newPaths: [String] = []
        for path in record.localImagePaths {
            if path.hasPrefix("mock://") { newPaths.append(path); continue }
            let src = documentsDirectory.appendingPathComponent(path)
            guard let data = try? Data(contentsOf: src) else { newPaths.append(path); continue }
            let encData = try crypto.encrypt(data)
            let encPath = path + ".enc"
            try encData.write(to: documentsDirectory.appendingPathComponent(encPath), options: [.atomic])
            try? fileManager.removeItem(at: src)
            newPaths.append(encPath)
        }

        var redacted = record
        redacted.title = Self.lockedPlaceholderTitle
        redacted.ocrText = ""
        redacted.summary = ""
        redacted.detailedContent = ""
        redacted.keyPoints = []
        redacted.definitions = []
        redacted.localImagePaths = newPaths
        redacted.isEncrypted = true
        return (redacted, blob)
    }

    // MARK: - Decrypt

    /// Returns the restored record and its todos. Also restores image files on disk.
    func decrypt(record: NoteRecord, blob: Data) throws -> (record: NoteRecord, todos: [NoteTodo]) {
        let payload = try JSONDecoder().decode(SensitivePayload.self, from: try crypto.decrypt(blob))

        var restoredPaths: [String] = []
        for path in record.localImagePaths {
            if path.hasPrefix("mock://") || !path.hasSuffix(".enc") { restoredPaths.append(path); continue }
            let encURL = documentsDirectory.appendingPathComponent(path)
            guard let encData = try? Data(contentsOf: encURL) else { restoredPaths.append(path); continue }
            let plainData = try crypto.decrypt(encData)
            let plainPath = String(path.dropLast(4)) // strip ".enc"
            try plainData.write(to: documentsDirectory.appendingPathComponent(plainPath), options: [.atomic])
            try? fileManager.removeItem(at: encURL)
            restoredPaths.append(plainPath)
        }

        var restored = record
        restored.title = payload.title
        restored.ocrText = payload.ocrText
        restored.summary = payload.summary
        restored.detailedContent = payload.detailedContent
        restored.keyPoints = payload.keyPoints
        restored.definitions = payload.definitions
        restored.localImagePaths = restoredPaths
        restored.isEncrypted = false
        return (restored, payload.todos)
    }

    /// In-memory decrypt for viewing (does NOT touch disk image files; used with decryptedImage()).
    func decryptForViewing(record: NoteRecord, blob: Data) throws -> (record: NoteRecord, todos: [NoteTodo]) {
        let payload = try JSONDecoder().decode(SensitivePayload.self, from: try crypto.decrypt(blob))
        var view = record
        view.title = payload.title
        view.ocrText = payload.ocrText
        view.summary = payload.summary
        view.detailedContent = payload.detailedContent
        view.keyPoints = payload.keyPoints
        view.definitions = payload.definitions
        return (view, payload.todos)
    }

    /// Loads and decrypts a single encrypted image (path ends in ".enc").
    func decryptedImage(atEncryptedPath path: String) -> UIImage? {
        let url = documentsDirectory.appendingPathComponent(path)
        guard let encData = try? Data(contentsOf: url),
              let plain = try? crypto.decrypt(encData) else { return nil }
        return UIImage(data: plain)
    }

    func writeBlob(_ blob: Data, for recordID: UUID) throws {
        try blob.write(to: blobURL(for: recordID), options: [.atomic])
    }

    func readBlob(for recordID: UUID) -> Data? {
        try? Data(contentsOf: blobURL(for: recordID))
    }

    func deleteBlob(for recordID: UUID) {
        try? fileManager.removeItem(at: blobURL(for: recordID))
    }
}
