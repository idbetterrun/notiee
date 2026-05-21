import Foundation

struct NoteRecord: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var eventID: UUID?
    var capturedAt: Date
    var localImagePath: String
    var title: String
    var ocrText: String
    var summary: String
    var processingState: AIProcessingState

    init(
        id: UUID = UUID(),
        eventID: UUID?,
        capturedAt: Date = Date(),
        localImagePath: String,
        title: String = "待处理记录",
        ocrText: String = "",
        summary: String = "",
        processingState: AIProcessingState = .pending
    ) {
        self.id = id
        self.eventID = eventID
        self.capturedAt = capturedAt
        self.localImagePath = localImagePath
        self.title = title
        self.ocrText = ocrText
        self.summary = summary
        self.processingState = processingState
    }
}
