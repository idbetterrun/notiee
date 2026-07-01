import Foundation
import UIKit

enum RecordSource: String, Codable, Sendable {
    case photo
    case spark
    case text
}

struct NoteRecord: Identifiable, Equatable, Hashable, Codable, Sendable {
    let id: UUID
    var eventID: UUID?
    var folderID: UUID?
    var capturedAt: Date
    var localImagePaths: [String]
    var title: String
    var ocrText: String
    var summary: String
    var detailedContent: String
    var processingState: AIProcessingState
    
    var keyPoints: [String]
    var definitions: [KeyDefinition]
    
    var isFavorite: Bool
    var isDeleted: Bool
    var editedAt: Date?
    var modelsUsed: [String]?
    var tokenUsage: Int
    var aiRetryCount: Int
    var deviceName: String?
    var source: RecordSource
    var isEncrypted: Bool

    init(
        id: UUID = UUID(),
        eventID: UUID? = nil,
        folderID: UUID? = nil,
        capturedAt: Date = Date(),
        localImagePaths: [String],
        title: String = "待处理记录",
        ocrText: String = "",
        summary: String = "",
        detailedContent: String = "",
        processingState: AIProcessingState = .pending,
        keyPoints: [String] = [],
        definitions: [KeyDefinition] = [],
        isFavorite: Bool = false,
        isDeleted: Bool = false,
        editedAt: Date? = nil,
        modelsUsed: [String]? = nil,
        tokenUsage: Int = 0,
        aiRetryCount: Int = 0,
        deviceName: String? = UIDevice.current.modelName,
        source: RecordSource = .photo,
        isEncrypted: Bool = false
    ) {
        self.id = id
        self.eventID = eventID
        self.folderID = folderID
        self.capturedAt = capturedAt
        self.localImagePaths = localImagePaths
        self.title = title
        self.ocrText = ocrText
        self.summary = summary
        self.detailedContent = detailedContent
        self.processingState = processingState
        self.keyPoints = keyPoints
        self.definitions = definitions
        self.isFavorite = isFavorite
        self.isDeleted = isDeleted
        self.editedAt = editedAt
        self.modelsUsed = modelsUsed
        self.tokenUsage = tokenUsage
        self.aiRetryCount = aiRetryCount
        self.deviceName = deviceName
        self.source = source
        self.isEncrypted = isEncrypted
    }

    private enum CodingKeys: String, CodingKey {
        case id, eventID, folderID, capturedAt, localImagePaths, title
        case ocrText, summary, detailedContent, processingState
        case keyPoints, definitions, isFavorite, isDeleted, editedAt
        case modelsUsed, tokenUsage, aiRetryCount, deviceName, source
        case isEncrypted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        eventID = try c.decodeIfPresent(UUID.self, forKey: .eventID)
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        capturedAt = try c.decode(Date.self, forKey: .capturedAt)
        localImagePaths = try c.decodeIfPresent([String].self, forKey: .localImagePaths) ?? []
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "待处理记录"
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        detailedContent = try c.decodeIfPresent(String.self, forKey: .detailedContent) ?? ""
        processingState = try c.decodeIfPresent(AIProcessingState.self, forKey: .processingState) ?? .pending
        keyPoints = try c.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        definitions = try c.decodeIfPresent([KeyDefinition].self, forKey: .definitions) ?? []
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        editedAt = try c.decodeIfPresent(Date.self, forKey: .editedAt)
        modelsUsed = try c.decodeIfPresent([String].self, forKey: .modelsUsed)
        tokenUsage = try c.decodeIfPresent(Int.self, forKey: .tokenUsage) ?? 0
        aiRetryCount = try c.decodeIfPresent(Int.self, forKey: .aiRetryCount) ?? 0
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName)
        source = try c.decodeIfPresent(RecordSource.self, forKey: .source) ?? .photo
        isEncrypted = try c.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false
    }
}

struct KeyDefinition: Equatable, Hashable, Codable, Sendable {
    var term: String
    var explanation: String
}
