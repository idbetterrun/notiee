import XCTest
@testable import Notiee

@MainActor
final class NoteCreateToolTests: XCTestCase {

    private func makeRecordManager() -> RecordManager {
        RecordManager(
            records: [],
            todos: [],
            recordStore: JSONNoteRecordStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        )
    }

    private func makeFolderManager() -> FolderTagManager {
        FolderTagManager(
            customFolders: [],
            customTags: EventTag.systemTags,
            eventTagMapping: [:],
            folderStore: JSONCustomFolderStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("json")),
            tagStore: JSONEventTagStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("json"))
        )
    }

    func testCreateMarksSparkSourceAndFilesIntoSparkFolder() async throws {
        let records = makeRecordManager()
        let folders = makeFolderManager()
        let tool = NoteCreateTool(recordManager: records, folderTagManager: folders)

        let result = try await tool.execute(parameters: ["title": "笔记A", "content": "正文"])

        XCTAssertTrue(result.success)
        let created = try XCTUnwrap(records.records.first)
        XCTAssertEqual(created.source, .spark)
        let sparkFolder = try XCTUnwrap(folders.customFolders.first { $0.name == "Spark 生成" })
        XCTAssertEqual(created.folderID, sparkFolder.id)
    }

    func testSecondCreateReusesSameFolder() async throws {
        let records = makeRecordManager()
        let folders = makeFolderManager()
        let tool = NoteCreateTool(recordManager: records, folderTagManager: folders)

        _ = try await tool.execute(parameters: ["title": "A"])
        _ = try await tool.execute(parameters: ["title": "B"])

        XCTAssertEqual(folders.customFolders.filter { $0.name == "Spark 生成" }.count, 1)
    }
}
