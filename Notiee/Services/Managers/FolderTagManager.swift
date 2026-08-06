import Combine
import Foundation

@MainActor
final class FolderTagManager: ObservableObject {
    @Published var customFolders: [CustomFolder]
    @Published var customTags: [EventTag]
    @Published var eventTagMapping: [String: UUID]

    let folderStore: CustomFolderPersisting
    let tagStore: EventTagPersisting

    init(
        customFolders: [CustomFolder],
        customTags: [EventTag],
        eventTagMapping: [String: UUID],
        folderStore: CustomFolderPersisting,
        tagStore: EventTagPersisting
    ) {
        var migratedFolders = customFolders
        var didMigrateNottiFolder = false
        for index in migratedFolders.indices
        where migratedFolders[index].systemRole == .nottiGenerated ||
            migratedFolders[index].name == "Spark 生成" ||
            migratedFolders[index].name == "Notti 生成" {
            if migratedFolders[index].systemRole != .nottiGenerated ||
                migratedFolders[index].name != Self.nottiFolderName {
                didMigrateNottiFolder = true
            }
            migratedFolders[index].systemRole = .nottiGenerated
            migratedFolders[index].name = Self.nottiFolderName
        }
        self.customFolders = migratedFolders
        self.customTags = customTags
        self.eventTagMapping = eventTagMapping
        self.folderStore = folderStore
        self.tagStore = tagStore
        if didMigrateNottiFolder {
            try? folderStore.saveFolders(migratedFolders)
        }
    }

    static var nottiFolderName: String { String(localized: "Notti 生成") }

    // MARK: - Folder CRUD

    func createFolder(name: String) {
        let folder = CustomFolder(name: name)
        customFolders.append(folder)
        persistFolders()
    }

    func renameFolder(id: UUID, newName: String) {
        if let index = customFolders.firstIndex(where: { $0.id == id }) {
            customFolders[index].name = newName
            persistFolders()
        }
    }

    func deleteFolder(id: UUID) {
        customFolders.removeAll { $0.id == id }
        persistFolders()
    }

    func createImportedFolder() -> UUID {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        let name = "\(formatter.string(from: Date())) 导入记录"
        let newFolder = CustomFolder(name: name)
        customFolders.append(newFolder)
        persistFolders()
        return newFolder.id
    }

    @discardableResult
    func findOrCreateFolder(named name: String) -> UUID {
        if name == Self.nottiFolderName,
           let existing = customFolders.first(where: { $0.systemRole == .nottiGenerated }) {
            return existing.id
        }
        if let existing = customFolders.first(where: { $0.name == name }) {
            return existing.id
        }
        let folder = CustomFolder(
            name: name,
            systemRole: name == Self.nottiFolderName ? .nottiGenerated : nil
        )
        customFolders.append(folder)
        persistFolders()
        return folder.id
    }

    // MARK: - Tag CRUD

    func createTag(name: String, colorHex: String) {
        let tag = EventTag(name: name, colorHex: colorHex, isSystem: false)
        customTags.append(tag)
        persistTags()
    }

    func updateTag(id: UUID, name: String, colorHex: String) {
        if let index = customTags.firstIndex(where: { $0.id == id && !$0.isSystem }) {
            customTags[index].name = name
            customTags[index].colorHex = colorHex
            persistTags()
        }
    }

    func deleteTag(id: UUID) {
        customTags.removeAll { $0.id == id && !$0.isSystem }
        let keysToRemove = eventTagMapping.filter { $0.value == id }.map { $0.key }
        for key in keysToRemove {
            eventTagMapping.removeValue(forKey: key)
        }
        persistTags()
    }

    func assignTagToEvent(eventTitle: String, tagID: UUID?) {
        if let tagID = tagID {
            eventTagMapping[eventTitle] = tagID
        } else {
            eventTagMapping.removeValue(forKey: eventTitle)
        }
        persistTags()
    }

    // MARK: - Persistence

    func persistFolders() {
        try? folderStore.saveFolders(customFolders)
    }

    func persistTags() {
        let mappingTags = eventTagMapping.map { key, value in
            EventTag(id: UUID(), name: "mapping_\(key)", colorHex: value.uuidString, isSystem: true)
        }
        let tagsToSave = customTags.filter { !$0.isSystem } + mappingTags
        try? tagStore.saveTags(tagsToSave)
    }
}
