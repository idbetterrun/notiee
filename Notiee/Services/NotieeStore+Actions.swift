import Foundation

extension NotieeStore {

    @discardableResult
    func capturePhoto(localImagePaths: [String]? = nil, eventID: UUID? = nil) -> NoteRecord {
        let resolvedEventID = eventID ?? currentEvent?.id
        let resolvedEventTitle: String? = {
            if let id = resolvedEventID {
                return events.first(where: { $0.id == id })?.title
            }
            return currentEvent?.title
        }()

        let record = NoteRecord(
            eventID: resolvedEventID,
            capturedAt: currentDate,
            localImagePaths: localImagePaths ?? [],
            title: resolvedEventTitle.map { "\($0) 拍记" } ?? "未分类拍记",
            processingState: .pending
        )

        records.insert(record, at: 0)
        persistRecords()

        if autoProcess && aiEnabled && autoProcessAfterCapture {
            enqueueProcessing(for: record)
        }

        return record
    }

    func processRecord(_ record: NoteRecord) {
        guard aiEnabled else { return }
        enqueueProcessing(for: record)
    }

    // MARK: - Record & Todo Mutations

    func addRecord(_ record: NoteRecord) {
        records.insert(record, at: 0)
        persistRecords()
    }

    func updateRecord(_ updated: NoteRecord) {
        guard let index = records.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        records[index] = updated
        persistRecords()
    }

    func toggleFavorite(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            return
        }
        records[index].isFavorite.toggle()
        persistRecords()
    }

    func toggleDeleted(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let becomingDeleted = !records[index].isDeleted
        records[index].isDeleted.toggle()
        if becomingDeleted {
            accumulateDeletedTokens(records[index].tokenUsage)
        }
        persistRecords()
    }

    func permanentlyDelete(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records[index]
        if !record.isDeleted {
            accumulateDeletedTokens(record.tokenUsage)
        }

        for path in record.localImagePaths {
            try? FileManager.default.removeItem(atPath: path)
        }

        todos.removeAll { $0.recordID == id }

        records.remove(at: index)
        persistRecords()
    }

    func toggleDeletedMultiple(ids: Set<UUID>, isDeleted: Bool) {
        for id in ids {
            if let index = records.firstIndex(where: { $0.id == id }) {
                let wasDeleted = records[index].isDeleted
                records[index].isDeleted = isDeleted
                if isDeleted && !wasDeleted {
                    accumulateDeletedTokens(records[index].tokenUsage)
                }
            }
        }
        persistRecords()
    }

    func permanentlyDeleteMultiple(ids: Set<UUID>) {
        records.removeAll { record in
            if ids.contains(record.id) {
                if !record.isDeleted {
                    accumulateDeletedTokens(record.tokenUsage)
                }
                for path in record.localImagePaths {
                    try? FileManager.default.removeItem(atPath: path)
                }
                todos.removeAll { $0.recordID == record.id }
                return true
            }
            return false
        }
        persistRecords()
    }

    private func accumulateDeletedTokens(_ tokens: Int) {
        let current = UserDefaults.standard.integer(forKey: "notiee.accumulatedDeletedTokens")
        UserDefaults.standard.set(current + tokens, forKey: "notiee.accumulatedDeletedTokens")
    }

    func addTodo(_ todo: NoteTodo) {
        todos.append(todo)
    }

    func replaceTodos(for recordID: UUID, with newTodos: [NoteTodo]) {
        todos.removeAll { $0.recordID == recordID }
        todos.append(contentsOf: newTodos)
    }

    func deleteTodo(id: UUID) {
        todos.removeAll { $0.id == id }
    }

    func toggleTodo(id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }
        todos[index].isCompleted.toggle()
        persistRecords()
    }

    func updateTodoContent(id: UUID, newContent: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else {
            return
        }
        todos[index].content = newContent
        persistRecords()
    }

    // MARK: - Custom Folders

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
        for i in 0..<records.count {
            if records[i].folderID == id {
                records[i].folderID = nil
            }
        }
        persistFolders()
        persistRecords()
    }

    func assignRecordToFolder(recordID: UUID, folderID: UUID?) {
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index].folderID = folderID
            persistRecords()
        }
    }

    // MARK: - Event Tags

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
        for i in 0..<events.count {
            if events[i].tagID == id {
                events[i].tagID = nil
            }
        }
        persistTags()
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

    func assignTagToEvent(eventID: UUID, tagID: UUID?) {
        if let index = events.firstIndex(where: { $0.id == eventID }) {
            events[index].tagID = tagID
            let title = events[index].title
            if let tagID = tagID {
                eventTagMapping[title] = tagID
            } else {
                eventTagMapping.removeValue(forKey: title)
            }
            persistTags()
        }
    }

    func addEvent(_ event: ScheduledEvent) {
        customEvents.append(event)
        persistCustomEvents()
        updateEventsList()
    }

    func deleteEvent(id: UUID) {
        customEvents.removeAll { $0.id == id }
        persistCustomEvents()
        updateEventsList()
    }

    func ignoreCalendarEvent(identifier: String, date: Date, future: Bool) {
        if future {
            ignoredCalendarEventKeys.insert("future_\(identifier)")
        } else {
            let dateStr = date.formatted(.dateTime.year().month().day())
            ignoredCalendarEventKeys.insert("once_\(identifier)_\(dateStr)")
        }
        persistIgnoredKeys()
        updateEventsList()
    }

    func restoreCalendarEvent(identifier: String) {
        ignoredCalendarEventKeys = ignoredCalendarEventKeys.filter { !$0.contains(identifier) }
        persistIgnoredKeys()
        updateEventsList()
    }

    func addStandaloneTodo(content: String, dueDate: Date?, hasReminder: Bool) {
        let todo = NoteTodo(recordID: nil, content: content, dueDate: dueDate, hasReminder: hasReminder)
        todos.append(todo)
    }

    // MARK: - Internal Helpers

    func persistIgnoredKeys() {
        if let data = try? JSONEncoder().encode(ignoredCalendarEventKeys) {
            UserDefaults.standard.set(data, forKey: "notiee.ignoredCalendarEventKeys")
        }
    }

    func isEventIgnored(_ event: ScheduledEvent) -> Bool {
        if case .systemCalendar(let identifier) = event.source {
            if ignoredCalendarEventKeys.contains("future_\(identifier)") {
                return true
            }
            let dateStr = event.startDate.formatted(.dateTime.year().month().day())
            if ignoredCalendarEventKeys.contains("once_\(identifier)_\(dateStr)") {
                return true
            }
        }
        return false
    }

    func updateEventsList() {
        let all = (customEvents + calendarEvents).sorted { $0.startDate < $1.startDate }
        self.allEvents = all
        self.events = all.filter { !isEventIgnored($0) }

        let advanceTime = UserDefaults.standard.integer(forKey: "notiee.notificationAdvanceTime")
        NotificationManager.shared.scheduleNotifications(for: self.events, advanceTimeMinutes: advanceTime)
        Task { await updateLiveActivity() }
    }

    func persistCustomEvents() {
        try? eventStore.saveEvents(customEvents)
    }

    func persistRecords() {
        do {
            try recordStore.saveRecords(records)
            lastPersistenceError = nil
        } catch {
            lastPersistenceError = error.localizedDescription
        }
    }

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
