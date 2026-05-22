import Foundation

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
    
    var isFavorite: Bool
    var isDeleted: Bool
    var editedAt: Date?
    var modelsUsed: [String]?
    var tokenUsage: Int

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
        isFavorite: Bool = false,
        isDeleted: Bool = false,
        editedAt: Date? = nil,
        modelsUsed: [String]? = nil,
        tokenUsage: Int = 0
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
        self.isFavorite = isFavorite
        self.isDeleted = isDeleted
        self.editedAt = editedAt
        self.modelsUsed = modelsUsed
        self.tokenUsage = tokenUsage
    }
}
