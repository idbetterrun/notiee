import Foundation
import ZIPFoundation
import UIKit

@MainActor
final class TMNExportService {
    static func export(record: NoteRecord, store: NotieeStore) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let attachmentsDir = tempDir.appendingPathComponent("attachments")
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        
        let iso8601 = ISO8601DateFormatter()
        let nowStr = iso8601.string(from: Date())
        
        var files: [TMNManifest.FileEntry] = []
        var attachmentRefs: [TMNContent.AttachmentRef] = []
        
        // Copy attachments
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        for (index, path) in record.localImagePaths.enumerated() {
            let srcURL = documentsDirectory.appendingPathComponent(path)
            let ext = srcURL.pathExtension.isEmpty ? "jpg" : srcURL.pathExtension
            let destName = "photo_\(String(format: "%03d", index + 1)).\(ext)"
            let destURL = attachmentsDir.appendingPathComponent(destName)
            
            if FileManager.default.fileExists(atPath: srcURL.path) {
                try FileManager.default.copyItem(at: srcURL, to: destURL)
                let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
                let size = attrs[.size] as? Int ?? 0
                
                files.append(TMNManifest.FileEntry(path: "attachments/\(destName)", size: size, mimeType: "image/\(ext)"))
                attachmentRefs.append(TMNContent.AttachmentRef(id: "img-\(index)", path: "attachments/\(destName)", type: "image", label: nil))
            }
        }
        
        // Build Content
        var appData: TMNContent.AppData? = nil
        let todos = store.todos(for: record).map { todo in
            TMNContent.TodoData(id: todo.id.uuidString, content: todo.content, isCompleted: todo.isCompleted, createdAt: iso8601.string(from: todo.createdAt))
        }
        
        let aiData = TMNContent.AIProcessingData(
            state: record.processingState.rawValue,
            ocrText: record.ocrText.isEmpty ? nil : record.ocrText,
            summary: record.summary.isEmpty ? nil : record.summary,
            detailedContent: record.detailedContent,
            todos: todos.isEmpty ? nil : todos,
            keyPoints: record.keyPoints.isEmpty ? nil : record.keyPoints,
            definitions: record.definitions.isEmpty ? nil : record.definitions.map { TMNContent.KeyDefinitionData(term: $0.term, explanation: $0.explanation) },
            modelsUsed: record.modelsUsed,
            tokenUsage: record.tokenUsage
        )
        
        var eventData: TMNContent.EventData? = nil
        if let eventID = record.eventID, let event = store.events.first(where: { $0.id == eventID }) {
            eventData = TMNContent.EventData(id: event.id.uuidString, title: event.title, type: event.kind.rawValue)
        }
        
        appData = TMNContent.AppData(notiee: TMNContent.NotieeAppData(event: eventData, aiProcessing: aiData, deviceName: record.deviceName))
        
        let content = TMNContent(
            id: record.id.uuidString,
            type: "record",
            title: record.title,
            description: nil,
            createdAt: iso8601.string(from: record.capturedAt),
            updatedAt: nowStr,
            tags: nil,
            encryption: TMNContent.Encryption(enabled: false),
            content: TMNContent.ContentData(format: "plain", text: "", attachmentsRefs: attachmentRefs.isEmpty ? nil : attachmentRefs),
            appData: appData
        )
        
        let contentData = try JSONEncoder().encode(content)
        try contentData.write(to: tempDir.appendingPathComponent("content.json"))
        
        // Build Manifest
        let manifest = TMNManifest(
            format: "tmn/zip/v1",
            metadata: TMNManifest.Metadata(
                app: "notiee",
                appVersion: "1.0.3",
                createdAt: nowStr,
                documentId: record.id.uuidString,
                encrypted: false
            ),
            files: files,
            content: TMNManifest.ContentSpec(main: "content.json", type: "record", schemaVersion: "1.0")
        )
        
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: tempDir.appendingPathComponent("manifest.json"))
        
        // Zip
        let sanitizedTitle = record.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let dateSuffix = record.capturedAt.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)).replacingOccurrences(of: "/", with: "-")
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(sanitizedTitle)_\(dateSuffix).tmn")
        
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        
        let archive = try Archive(url: zipURL, accessMode: .create)
        try archive.addEntry(with: "manifest.json", fileURL: tempDir.appendingPathComponent("manifest.json"))
        try archive.addEntry(with: "content.json", fileURL: tempDir.appendingPathComponent("content.json"))
        
        for file in files {
            let localPath = tempDir.appendingPathComponent(file.path)
            try archive.addEntry(with: file.path, fileURL: localPath)
        }
        
        return zipURL
    }
}
