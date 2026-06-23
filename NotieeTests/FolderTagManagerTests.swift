import XCTest
@testable import Notiee

@MainActor
final class FolderTagManagerTests: XCTestCase {

    // MARK: - Folder tests

    func testCreateFolder() {
        let mgr = makeManager()
        mgr.createFolder(name: "Test Folder")
        XCTAssertEqual(mgr.customFolders.count, 1)
        XCTAssertEqual(mgr.customFolders.first?.name, "Test Folder")
    }

    func testRenameFolder() {
        let folder = CustomFolder(name: "Old")
        let mgr = makeManager(folders: [folder])
        mgr.renameFolder(id: folder.id, newName: "New")
        XCTAssertEqual(mgr.customFolders.first?.name, "New")
    }

    func testDeleteFolder() {
        let folder = CustomFolder(name: "ToDelete")
        let mgr = makeManager(folders: [folder])
        mgr.deleteFolder(id: folder.id)
        XCTAssertTrue(mgr.customFolders.isEmpty)
    }

    func testCreateImportedFolderReturnsValidUUID() {
        let mgr = makeManager()
        let id = mgr.createImportedFolder()
        XCTAssertEqual(mgr.customFolders.count, 1)
        XCTAssertEqual(mgr.customFolders.first?.id, id)
        XCTAssertTrue(mgr.customFolders.first?.name.contains("导入记录") ?? false)
    }

    func testFindOrCreateFolderCreatesWhenMissing() {
        let mgr = makeManager()
        let id = mgr.findOrCreateFolder(named: "Spark 生成")
        XCTAssertEqual(mgr.customFolders.count, 1)
        XCTAssertEqual(mgr.customFolders.first?.id, id)
        XCTAssertEqual(mgr.customFolders.first?.name, "Spark 生成")
    }

    func testFindOrCreateFolderReusesExisting() {
        let existing = CustomFolder(name: "Spark 生成")
        let mgr = makeManager(folders: [existing])
        let id = mgr.findOrCreateFolder(named: "Spark 生成")
        XCTAssertEqual(id, existing.id)
        XCTAssertEqual(mgr.customFolders.count, 1)
    }

    // MARK: - Tag tests

    func testCreateTag() {
        let mgr = makeManager()
        mgr.createTag(name: "Important", colorHex: "#FF0000")
        XCTAssertEqual(mgr.customTags.count, EventTag.systemTags.count + 1)
        let created = mgr.customTags.last
        XCTAssertEqual(created?.name, "Important")
        XCTAssertEqual(created?.colorHex, "#FF0000")
        XCTAssertFalse(created?.isSystem ?? true)
    }

    func testUpdateTag() {
        var tag = EventTag(name: "Old", colorHex: "#000")
        let mgr = makeManager(tags: EventTag.systemTags + [tag])
        mgr.updateTag(id: tag.id, name: "New", colorHex: "#FFF")
        let updated = mgr.customTags.first { $0.id == tag.id }
        XCTAssertEqual(updated?.name, "New")
        XCTAssertEqual(updated?.colorHex, "#FFF")
    }

    func testUpdateTagDoesNotAffectSystemTags() {
        let mgr = makeManager()
        let sysTag = EventTag.personal
        mgr.updateTag(id: sysTag.id, name: "Hacked", colorHex: "#000")
        let unchanged = mgr.customTags.first { $0.id == sysTag.id }
        XCTAssertEqual(unchanged?.name, "个人") // unchanged
    }

    func testDeleteTagCleansMapping() {
        let tag = EventTag(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
                           name: "Test", colorHex: "#FF0")
        let mgr = makeManager(
            tags: EventTag.systemTags + [tag],
            mapping: ["SomeEvent": tag.id]
        )
        mgr.deleteTag(id: tag.id)
        XCTAssertNil(mgr.eventTagMapping["SomeEvent"])
    }

    func testDeleteTagCannotDeleteSystemTags() {
        let mgr = makeManager()
        let countBefore = mgr.customTags.count
        mgr.deleteTag(id: EventTag.personal.id)
        XCTAssertEqual(mgr.customTags.count, countBefore)
    }

    func testAssignTagToEvent() {
        let mgr = makeManager()
        mgr.assignTagToEvent(eventTitle: "Math 101", tagID: EventTag.course.id)
        XCTAssertEqual(mgr.eventTagMapping["Math 101"], EventTag.course.id)
    }

    func testAssignTagToEventRemovesMappingWhenNil() {
        let mgr = makeManager(mapping: ["Math 101": EventTag.course.id])
        mgr.assignTagToEvent(eventTitle: "Math 101", tagID: nil)
        XCTAssertNil(mgr.eventTagMapping["Math 101"])
    }

    // MARK: - Persistence

    func testPersistFoldersSavesToStore() throws {
        let folderStore = makeFolderStore()
        let mgr = FolderTagManager(
            customFolders: [],
            customTags: EventTag.systemTags,
            eventTagMapping: [:],
            folderStore: folderStore,
            tagStore: makeTagStore()
        )
        mgr.createFolder(name: "Persisted")
        let loaded = try folderStore.loadFolders()
        XCTAssertEqual(loaded.first?.name, "Persisted")
    }

    func testPersistTagsIncludesMappingTags() throws {
        let tagStore = makeTagStore()
        let tag = EventTag(name: "Custom", colorHex: "#ABC", isSystem: false)
        let mgr = FolderTagManager(
            customFolders: [],
            customTags: EventTag.systemTags + [tag],
            eventTagMapping: ["EventA": tag.id],
            folderStore: makeFolderStore(),
            tagStore: tagStore
        )
        mgr.persistTags()
        let loaded = try tagStore.loadTags()
        let mappingTag = loaded.first { $0.name.hasPrefix("mapping_") }
        XCTAssertNotNil(mappingTag)
        XCTAssertEqual(mappingTag?.colorHex, tag.id.uuidString)
    }

    // MARK: - Helpers

    private func makeManager(
        folders: [CustomFolder] = [],
        tags: [EventTag] = EventTag.systemTags,
        mapping: [String: UUID] = [:]
    ) -> FolderTagManager {
        FolderTagManager(
            customFolders: folders,
            customTags: tags,
            eventTagMapping: mapping,
            folderStore: makeFolderStore(),
            tagStore: makeTagStore()
        )
    }

    private func makeFolderStore() -> JSONCustomFolderStore {
        JSONCustomFolderStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json"))
    }

    private func makeTagStore() -> JSONEventTagStore {
        JSONEventTagStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json"))
    }
}
