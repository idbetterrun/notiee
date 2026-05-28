import Foundation

extension NotieeStore {

    // MARK: - Calendar Sync

    func syncCalendar() {
        Task {
            let granted = await CalendarService.shared.requestAccess()
            if granted {
                let fetchedEvents = CalendarService.shared.fetchEvents(currentDate: currentDate)
                await MainActor.run {
                    self.calendarEvents = fetchedEvents.map { event in
                        var newEvent = event
                        newEvent.tagID = self.eventTagMapping[event.title]
                        return newEvent
                    }
                    self.updateEventsList()
                }
            }
        }
    }

    // MARK: - Live Activity

    func updateLiveActivity() async {
        let isEnabled = UserDefaults.standard.bool(forKey: "notiee.liveActivityEnabled")
        guard isEnabled else {
            LiveActivityManager.shared.endActivity()
            return
        }

        let checkDate = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ? currentDate : Date()

        if let event = scheduleMatcher.currentEvent(from: events, at: checkDate) {
            guard !event.isAllDay else {
                LiveActivityManager.shared.endActivity()
                return
            }
            guard !liveActivityDisabledEventIDs.contains(event.id) else {
                LiveActivityManager.shared.endActivity()
                return
            }
            LiveActivityManager.shared.startActivity(for: event)
        } else {
            LiveActivityManager.shared.endActivity()
        }
    }

    func toggleLiveActivityForEvent(_ eventID: UUID) {
        if liveActivityDisabledEventIDs.contains(eventID) {
            liveActivityDisabledEventIDs.remove(eventID)
        } else {
            liveActivityDisabledEventIDs.insert(eventID)
            LiveActivityManager.shared.endActivity()
        }
        if let data = try? JSONEncoder().encode(liveActivityDisabledEventIDs) {
            UserDefaults.standard.set(data, forKey: "notiee.liveActivityDisabledEventIDs")
        }
        Task { await updateLiveActivity() }
    }

    // MARK: - AI Processing Pipeline

    func retryAIProcessing(for recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        var record = records[index]
        guard record.processingState == .failed else { return }

        record.processingState = .pending
        records[index] = record
        persistRecords()

        enqueueProcessing(for: record)
    }

    func updateRecordEvent(recordID: UUID, newEventID: UUID?) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].eventID = newEventID
        persistRecords()
    }

    // MARK: - Private Pipeline

    internal func enqueueProcessing(for record: NoteRecord) {
        guard aiEnabled else { return }
        let recordID = record.id
        let service = aiService

        Task {
            await MainActor.run { self.setProcessingState(.processing, for: recordID) }

            do {
                let eventTitle = self.events.first(where: { $0.id == record.eventID })?.title
                let result = try await service.process(imagePaths: record.localImagePaths, eventTitle: eventTitle)

                await MainActor.run { self.applyAIResult(result, to: recordID) }
            } catch {
                await MainActor.run {
                    self.setProcessingState(.failed, for: recordID)
                    print("AI Processing failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func setProcessingState(_ state: AIProcessingState, for recordID: UUID) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else {
            return
        }
        records[index].processingState = state
        persistRecords()
    }

    private func applyAIResult(_ result: AIProcessingResult, to recordID: UUID) {
        if let index = records.firstIndex(where: { $0.id == recordID }) {
            records[index].title = result.title
            records[index].ocrText = result.ocrText
            records[index].summary = result.summary
            records[index].detailedContent = result.detailedContent
            records[index].keyPoints = result.keyPoints
            records[index].definitions = result.definitions
            records[index].modelsUsed = result.modelsUsed
            records[index].tokenUsage = result.tokenUsage
            records[index].processingState = .completed

            persistRecords()

            for content in result.todos {
                let todo = NoteTodo(recordID: recordID, content: content)
                addTodo(todo)
            }
        }
    }
}
