import Combine
import Foundation

@MainActor
final class RecordDetailViewModel: ObservableObject {
    let record: NoteRecord

    private let store: NotieeStore

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

    private var fallbackSummary: String {
        switch record.processingState {
        case .pending, .processing:
            "AI 正在整理这条记录。"
        case .completed:
            "这条记录暂时没有摘要。"
        case .failed:
            "处理失败后可以稍后重试。"
        }
    }

    func toggleTodo(id: UUID) {
        store.toggleTodo(id: id)
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
        store.events
    }
}
