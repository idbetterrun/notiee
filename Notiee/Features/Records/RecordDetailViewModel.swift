import Combine
import Foundation

@MainActor
final class RecordDetailViewModel: ObservableObject {
    let record: NoteRecord

    let store: NotieeStore

    init(record: NoteRecord, store: NotieeStore) {
        self.record = record
        self.store = store
    }

    var eventTitle: String {
        store.eventTitle(for: record) ?? "未分类"
    }

    var statusTitle: String {
        switch record.processingState {
        case .pending:
            "等待 AI 处理"
        case .processing:
            "AI 处理中"
        case .completed:
            "已生成摘要"
        case .failed:
            "处理失败"
        case .deadLetter:
            "已达最大重试次数"
        }
    }

    var summaryText: String {
        guard !record.summary.isEmpty else {
            return fallbackSummary
        }

        return record.summary
    }

    var ocrText: String {
        guard !record.ocrText.isEmpty else {
            return "OCR 结果生成后会显示在这里。"
        }

        return record.ocrText
    }

    var todos: [NoteTodo] {
        store.todos(for: record)
    }

    // MARK: - 区块可见性（按来源差异化）

    /// AI 摘要：拍照记录始终展示；Spark 记录仅当有真摘要且不等于正文时展示；纯文本不展示。
    var showsSummarySection: Bool {
        switch record.source {
        case .photo: return true
        case .spark: return !record.summary.isEmpty && record.summary != record.detailedContent
        case .text: return false
        }
    }

    /// OCR 原文只对拍照记录有意义（纯文本/Spark 无图、无 OCR）。
    var showsOCRSection: Bool {
        record.source == .photo
    }

    /// 仅拍照记录会 AI 抽取待办，故只有它在待办为空时展示「将自动提取」占位。
    var showsTodoPlaceholder: Bool {
        record.source == .photo
    }

    private var fallbackSummary: String {
        switch record.processingState {
        case .pending, .processing:
            "AI 正在整理这条记录。"
        case .completed:
            "这条记录暂时没有摘要。"
        case .failed:
            "处理失败后可以稍后重试。"
        case .deadLetter:
            "处理已达最大重试次数，请检查 API 配置后手动重试。"
        }
    }

    func toggleTodo(id: UUID) {
        store.toggleTodo(id: id)
    }
    
    func deleteTodo(id: UUID) {
        store.deleteTodo(id: id)
    }
    
    func deleteRecord() {
        store.toggleDeleted(id: record.id)
    }
    
    func saveEdits(updatedRecord: NoteRecord, updatedTodos: [NoteTodo]) {
        store.updateRecord(updatedRecord)
        store.replaceTodos(for: updatedRecord.id, with: updatedTodos)
    }

    func processRecord() {
        store.processRecord(record)
    }

    func retryProcessing() {
        store.retryAIProcessing(for: record.id)
    }

    func reassignEvent(to eventID: UUID?) {
        store.updateRecordEvent(recordID: record.id, newEventID: eventID)
    }

    var availableEvents: [ScheduledEvent] {
        var seen: Set<String> = []
        var result: [ScheduledEvent] = []
        for event in store.events {
            let normalized = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !CalendarService.shared.isHolidayEvent(event) else { continue }
            if !seen.contains(normalized) {
                seen.insert(normalized)
                result.append(event)
            }
        }
        return result
    }
    
    func reassignFolder(to folderID: UUID?) {
        store.assignRecordToFolder(recordID: record.id, folderID: folderID)
    }
    
    var availableFolders: [CustomFolder] {
        store.customFolders
    }

    var continuationRecord: NoteRecord? {
        guard UserDefaults.standard.bool(forKey: UDK.labDeepAssociationModeEnabled) else { return nil }
        guard let eventID = record.eventID else { return nil }

        let sameEventRecords = store.records
            .filter { $0.eventID == eventID && $0.id != record.id && !$0.isDeleted }
            .sorted { $0.capturedAt > $1.capturedAt }

        guard let previous = sameEventRecords.first else { return nil }
        let interval = record.capturedAt.timeIntervalSince(previous.capturedAt)
        guard interval > 0, interval < 172_800 else { return nil } // within 2 days

        return previous
    }

    // MARK: - 相关内容（语义联想）

    /// 被动推荐的质量门槛：高于 Spark 主动搜索的阈值，宁缺毋滥。需在真机数据上调优。
    private static let relatedThreshold: Float = 0.6
    private static let relatedLimit = 3

    /// 详情页「相关内容」。异步语义计算，算好后填充；空则该区块自动隐藏。
    @Published private(set) var relatedRecords: [NoteRecord] = []

    /// 固定走本地向量 + 独立索引：浏览时不触发云端 embedding（零成本、不外传）。
    private lazy var relatedEngine = SemanticSearchEngine(
        embeddingService: LocalEmbeddingService(),
        index: .relatedNotes
    )

    func loadRelatedRecords() async {
        guard UserDefaults.standard.bool(forKey: UDK.labDeepAssociationModeEnabled) else {
            relatedRecords = []
            return
        }

        let candidates = store.records.filter {
            !$0.isDeleted && $0.id != record.id && $0.processingState == .completed
        }
        relatedRecords = await relatedEngine.related(
            to: record,
            in: candidates,
            limit: Self.relatedLimit,
            threshold: Self.relatedThreshold
        )
    }
}
