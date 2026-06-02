import Foundation
import UIKit
import ZIPFoundation

@MainActor
final class TMNImportService {
    static func importTMN(url: URL) async throws -> (NoteRecord, [NoteTodo]) {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        try FileManager.default.unzipItem(at: url, to: tempDir)
        
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(TMNManifest.self, from: manifestData)
        
        guard manifest.format == "tmn/zip/v1" else {
            throw NSError(domain: "TMNImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported format"])
        }
        
        let contentURL = tempDir.appendingPathComponent(manifest.content.main)
        let contentData = try Data(contentsOf: contentURL)
        let content = try JSONDecoder().decode(TMNContent.self, from: contentData)
        
        var localImagePaths: [String] = []
        if let refs = content.content.attachmentsRefs {
            for ref in refs {
                let sourcePath = tempDir.appendingPathComponent(ref.path)
                if FileManager.default.fileExists(atPath: sourcePath.path) {
                    if let imgData = try? Data(contentsOf: sourcePath), let image = UIImage(data: imgData) {
                        if let destPath = try? LocalImageStore.shared.saveImage(image) {
                            localImagePaths.append(destPath)
                        }
                    }
                }
            }
        }
        
        let aiData = content.appData?.notiee?.aiProcessing
        let stateStr = aiData?.state ?? "completed"
        let processingState = AIProcessingState(rawValue: stateStr) ?? .completed
        
        let iso8601 = ISO8601DateFormatter()
        let capturedAt = iso8601.date(from: content.createdAt) ?? Date()
        
        let newRecord = NoteRecord(
            id: UUID(),
            eventID: nil,
            folderID: nil,
            capturedAt: capturedAt,
            localImagePaths: localImagePaths,
            title: content.title,
            ocrText: aiData?.ocrText ?? "",
            summary: aiData?.summary ?? "",
            detailedContent: aiData?.detailedContent ?? "",
            processingState: processingState,
            keyPoints: aiData?.keyPoints ?? [],
            definitions: (aiData?.definitions ?? []).map { KeyDefinition(term: $0.term, explanation: $0.explanation) },
            isFavorite: false,
            isDeleted: false,
            editedAt: nil,
            modelsUsed: aiData?.modelsUsed ?? [],
            tokenUsage: aiData?.tokenUsage ?? 0,
            deviceName: content.appData?.notiee?.deviceName
        )
        
        var parsedTodos: [NoteTodo] = []
        if let importedTodos = aiData?.todos {
            for t in importedTodos {
                let todo = NoteTodo(
                    recordID: newRecord.id,
                    content: t.content,
                    isCompleted: t.isCompleted,
                    createdAt: iso8601.date(from: t.createdAt) ?? Date()
                )
                parsedTodos.append(todo)
            }
        }
        
        return (newRecord, parsedTodos)
    }
}
