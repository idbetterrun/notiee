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
        guard UserDefaults.standard.bool(forKey: "labDeepAssociationModeEnabled") else { return nil }
        guard let eventID = record.eventID else { return nil }

        let sameEventRecords = store.records
            .filter { $0.eventID == eventID && $0.id != record.id && !$0.isDeleted }
            .sorted { $0.capturedAt > $1.capturedAt }

        guard let previous = sameEventRecords.first else { return nil }
        let interval = record.capturedAt.timeIntervalSince(previous.capturedAt)
        guard interval > 0, interval < 172_800 else { return nil } // within 2 days

        return previous
    }

    var relatedRecords: [NoteRecord] {
        guard UserDefaults.standard.bool(forKey: "labDeepAssociationModeEnabled") else { return [] }

        let allRecords = store.records.filter { !$0.isDeleted && $0.id != record.id && $0.processingState == .completed }

        let sameEvent = allRecords
            .filter { $0.eventID == record.eventID }
            .sorted { $0.capturedAt > $1.capturedAt }
            .prefix(3)

        let sameTitle = allRecords
            .filter { $0.title == record.title && $0.eventID != record.eventID }
            .prefix(2)

        return Array(sameEvent) + Array(sameTitle)
    }
}
