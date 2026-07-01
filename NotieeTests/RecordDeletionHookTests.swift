import XCTest
@testable import Notiee

@MainActor
final class RecordDeletionHookTests: XCTestCase {
    private func makeManager(_ records: [NoteRecord]) -> RecordManager {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID()).json")
        return RecordManager(
            records: records,
            todos: [],
            recordStore: JSONNoteRecordStore(fileURL: url),
            todoStore: JSONNoteTodoStore(fileURL: url.appendingPathExtension("todos"))
        )
    }

    func testPermanentlyDelete_firesHookWithDeletedID() {
        let rec = NoteRecord(localImagePaths: [], title: "t", processingState: .completed)
        let mgr = makeManager([rec])
        var captured: [UUID] = []
        mgr.onRecordsDeleted = { captured.append(contentsOf: $0) }

        mgr.permanentlyDelete(id: rec.id)

        XCTAssertEqual(captured, [rec.id])
    }

    func testPermanentlyDeleteMultiple_firesHookWithAllIDs() {
        let a = NoteRecord(localImagePaths: [], title: "a", processingState: .completed)
        let b = NoteRecord(localImagePaths: [], title: "b", processingState: .completed)
        let mgr = makeManager([a, b])
        var captured: Set<UUID> = []
        mgr.onRecordsDeleted = { captured.formUnion($0) }

        mgr.permanentlyDeleteMultiple(ids: [a.id, b.id])

        XCTAssertEqual(captured, [a.id, b.id])
    }
}
