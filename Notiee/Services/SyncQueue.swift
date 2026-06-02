import Foundation

/// Defines a sync operation for future backend integration.
enum SyncOperation {
    case create(NoteRecord)
    case update(NoteRecord)
    case delete(UUID)
}

/// FIFO queue for pending backend sync operations.
/// Operations are deduplicated: multiple updates to the same record
/// are collapsed into the latest version.
@MainActor
final class SyncQueue: ObservableObject {
    @Published private(set) var pendingCount = 0
    @Published var syncStatus: SyncStatus = .idle

    private var operations: [SyncOperation] = []

    var isOnline: Bool { NetworkMonitor.shared.isConnected }

    enum SyncStatus {
        case idle
        case syncing
        case offline
        case error(String)
    }

    func enqueue(_ operation: SyncOperation) {
        // Deduplicate: replace earlier updates to same record
        switch operation {
        case .update(let record):
            operations.removeAll {
                if case .update(let existing) = $0, existing.id == record.id { return true }
                return false
            }
        case .create, .delete:
            break
        }

        operations.append(operation)
        pendingCount = operations.count

        if isOnline {
            syncStatus = .idle
        } else {
            syncStatus = .offline
        }
    }

    func processPending() async {
        guard isOnline, !operations.isEmpty else { return }

        syncStatus = .syncing
        let batch = operations
        operations.removeAll()
        pendingCount = 0

        // In the future, batch would be sent to backend.
        // For now, operations are simply cleared (local-first architecture).
        _ = batch

        syncStatus = .idle
    }

    func clear() {
        operations.removeAll()
        pendingCount = 0
        syncStatus = .idle
    }
}
