import XCTest
@testable import Notiee

@MainActor
final class NewUIPreviewStateTests: XCTestCase {
    func testHeroContextRecommendsExpectedTodaySection() {
        XCTAssertEqual(NewUIPreviewHeroContext.activeEvent.recommendedTodaySection, .schedule)
        XCTAssertEqual(NewUIPreviewHeroContext.imminentEvent.recommendedTodaySection, .schedule)
        XCTAssertEqual(NewUIPreviewHeroContext.dueTodo.recommendedTodaySection, .todos)
        XCTAssertEqual(NewUIPreviewHeroContext.recordMomentum.recommendedTodaySection, .records)
        XCTAssertEqual(NewUIPreviewHeroContext.calm.recommendedTodaySection, .records)
    }

    func testManualSectionSelectionPersistsDuringSameTodayVisit() {
        let state = makeState(scenario: .activeEvent)

        state.selectTodaySection(.todos)
        state.applyScenario()

        XCTAssertEqual(state.selectedTodaySection, .todos)
    }

    func testScenarioChangeResetsSectionUsingNewHero() {
        let state = makeState(scenario: .activeEvent)
        state.selectTodaySection(.records)

        state.scenario = .dueTodo

        XCTAssertEqual(state.selectedTodaySection, .todos)
        XCTAssertEqual(state.hero.context, .dueTodo)
    }

    func testNewTodayVisitResetsSectionUsingCurrentHero() {
        let state = makeState(scenario: .imminentEvent)
        state.selectTodaySection(.records)
        state.select(.records)

        state.select(.today)

        XCTAssertEqual(state.destination, .today)
        XCTAssertEqual(state.selectedTodaySection, .schedule)
    }

    func testFixtureIdentityAndDatesAreStable() {
        let first = NewUIPreviewFixtures.records
        let second = NewUIPreviewFixtures.records

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.map { $0.record.capturedAt }, second.map { $0.record.capturedAt })
        XCTAssertEqual(NewUIPreviewFixtures.referenceDate, Date(timeIntervalSince1970: 1_785_888_000))
    }

    func testFixturesCoverMediaCountsAndProcessingStates() {
        let fixtures = NewUIPreviewFixtures.records

        XCTAssertTrue(Set(fixtures.map(\.media.count)).isSuperset(of: [0, 1, 2, 3, 4, 5, 6]))
        XCTAssertTrue(fixtures.contains { $0.record.processingState == .pending })
        XCTAssertTrue(fixtures.contains { $0.record.processingState == .processing })
        XCTAssertTrue(fixtures.contains { $0.record.processingState == .failed })
        XCTAssertTrue(fixtures.contains { $0.record.isEncrypted })
        XCTAssertTrue(fixtures.contains { !$0.record.ocrText.isEmpty })
        XCTAssertTrue(fixtures.contains { !$0.todos.isEmpty })
        XCTAssertEqual(Set(fixtures.map(\.previewSource)), Set(NewUIPreviewRecordSource.allCases))
    }

    func testCardSummaryNeverFallsBackToDetailOrOCR() throws {
        let fixture = try XCTUnwrap(NewUIPreviewFixtures.records.first { fixture in
            fixture.record.summary.isEmpty && !fixture.record.detailedContent.isEmpty
        })

        XCTAssertEqual(fixture.cardSummary, "")
    }

    func testTodayRecordProjectsSummaryAndFirstMediaThumbnail() throws {
        let state = makeState(scenario: .activeEvent)
        let projected = try XCTUnwrap(state.todayRecords.first)
        let fixture = try XCTUnwrap(state.recordFixture(id: projected.id))

        XCTAssertEqual(projected.summary, fixture.record.summary)
        XCTAssertEqual(projected.thumbnailImageName, fixture.media.first?.imageName)
    }

    func testRecordMomentumUsesAllSafeTodayFixturesAndKeepsHeroCountConsistent() {
        let state = makeState(scenario: .recordMomentum)
        let safeFixtureCount = state.recordFixtures.filter {
            !$0.record.isEncrypted && !$0.record.isDeleted
        }.count

        XCTAssertGreaterThan(state.todayRecords.count, 3)
        XCTAssertEqual(state.todayRecords.count, safeFixtureCount)
        XCTAssertEqual(state.statistics.todayCount, state.todayRecords.count)
        XCTAssertTrue(state.hero.title.contains("\(state.todayRecords.count)"))
    }

    func testSearchMatchesOnlyTitleAndSummary() {
        let state = makeState()

        state.recordsSearchQuery = "路线图"
        XCTAssertEqual(state.filteredRecordFixtures.map(\.record.title), ["产品周会：Q3 路线图"])

        state.recordsSearchQuery = "三项重点"
        XCTAssertEqual(state.filteredRecordFixtures.map(\.record.title), ["产品周会：Q3 路线图"])

        state.recordsSearchQuery = "无框 Hero 草图"
        XCTAssertTrue(state.filteredRecordFixtures.isEmpty, "Detailed content and todos must not be searchable")

        state.recordsSearchQuery = "Whiteboard notes"
        XCTAssertTrue(state.filteredRecordFixtures.isEmpty, "OCR must not be searchable")
    }

    func testEncryptedRecordNeverAppearsInSearchResults() {
        let state = makeState()

        state.recordsSearchQuery = "private roadmap sentinel"
        XCTAssertTrue(state.filteredRecordFixtures.isEmpty)

        state.recordsSearchQuery = "confidential summary sentinel"
        XCTAssertTrue(state.filteredRecordFixtures.isEmpty)

        state.recordsSearchQuery = ""
        XCTAssertTrue(state.filteredRecordFixtures.contains { $0.record.isEncrypted })
    }

    func testRecordsFilterIncludesOnlyTheSelectedPreviewSource() {
        let state = makeState()

        for filter in NewUIPreviewRecordsFilter.allCases where filter != .all {
            state.selectedRecordsFilter = filter

            XCTAssertFalse(state.filteredRecordFixtures.isEmpty, "filter: \(filter)")
            XCTAssertTrue(
                state.filteredRecordFixtures.allSatisfy { filter.includes($0.previewSource) },
                "filter: \(filter)"
            )
        }
    }

    func testRecordsSearchAndFilterAreCombined() {
        let state = makeState()
        state.selectedRecordsFilter = .photo
        state.recordsSearchQuery = "路线图"

        XCTAssertEqual(state.filteredRecordFixtures.map(\.record.title), ["产品周会：Q3 路线图"])

        state.selectedRecordsFilter = .audio
        XCTAssertTrue(state.filteredRecordFixtures.isEmpty)

        state.recordsSearchQuery = "语音"
        XCTAssertEqual(state.filteredRecordFixtures.map(\.previewSource), [.audio])
    }

    func testAllScopeExcludesDeletedRecordsAndTrashContainsOnlyDeletedRecords() {
        let state = makeState()

        XCTAssertFalse(state.filteredRecordFixtures.contains { $0.record.isDeleted })

        state.selectRecordsScope(.trash)

        XCTAssertFalse(state.filteredRecordFixtures.isEmpty)
        XCTAssertTrue(state.filteredRecordFixtures.allSatisfy { $0.record.isDeleted })
    }

    func testSmartRecordScopesMatchTheirDefinitions() {
        let state = makeState()

        state.selectRecordsScope(.favorites)
        XCTAssertTrue(state.filteredRecordFixtures.allSatisfy {
            $0.record.isFavorite && !$0.record.isDeleted
        })

        state.selectRecordsScope(.today)
        XCTAssertTrue(state.filteredRecordFixtures.allSatisfy {
            Calendar.current.isDate(
                $0.record.capturedAt,
                inSameDayAs: NewUIPreviewFixtures.referenceDate
            ) && !$0.record.isDeleted
        })

        state.selectRecordsScope(.pending)
        XCTAssertEqual(state.filteredRecordFixtures.map(\.record.processingState), [.pending])
    }

    func testUnclassifiedIncludesEventLinkedRecordWithoutFolder() throws {
        let state = makeState()
        state.selectRecordsScope(.unclassified)

        let audio = try XCTUnwrap(
            state.filteredRecordFixtures.first { $0.previewSource == .audio }
        )
        XCTAssertEqual(audio.eventName, "散步")
        XCTAssertNil(audio.folderName)
    }

    func testFolderAndEventScopesCombineWithSourceAndSearchFilters() {
        let state = makeState()
        state.selectRecordsScope(.folder("工作"))
        state.selectedRecordsFilter = .notti
        state.recordsSearchQuery = "发布复盘"

        XCTAssertEqual(
            state.filteredRecordFixtures.map(\.record.title),
            ["Notti 整理的发布复盘"]
        )

        state.selectRecordsScope(.event("产品周会"))
        state.selectedRecordsFilter = .photo
        state.recordsSearchQuery = "路线图"

        XCTAssertEqual(
            state.filteredRecordFixtures.map(\.record.title),
            ["产品周会：Q3 路线图"]
        )
    }

    func testRecordScopeListsAndScrollRevisionAreDeterministic() {
        let state = makeState()
        let initialRevision = state.recordsScrollRevision

        XCTAssertEqual(state.recordFolderNames, ["保险箱", "工作", "灵感", "生活", "阅读"])
        XCTAssertEqual(state.recordEventNames, ["产品周会", "散步", "私人日程", "设计评审"])

        state.selectRecordsScope(.folder("工作"))
        XCTAssertEqual(state.recordsScrollRevision, initialRevision + 1)
        XCTAssertEqual(state.selectedRecordsScope.title, "工作")

        state.selectRecordsScope(.folder("工作"))
        XCTAssertEqual(state.recordsScrollRevision, initialRevision + 1)
    }

    func testPreviewUsesTheCanonicalBrandGreen() {
        XCTAssertEqual(NewUIPreviewBrand.accentHex, "#09C576")
        XCTAssertTrue(NewUIPreviewHeroContext.activeEvent.showsAurora)
        XCTAssertTrue(
            [
                NewUIPreviewHeroContext.dueTodo,
                .imminentEvent,
                .recordMomentum,
                .calm
            ].allSatisfy { !$0.showsAurora }
        )
    }

    func testAudioAndNottiFixturesUseStablePreviewSources() throws {
        let audio = try XCTUnwrap(NewUIPreviewFixtures.records.first { $0.previewSource == .audio })
        let notti = try XCTUnwrap(NewUIPreviewFixtures.records.first { $0.previewSource == .notti })

        XCTAssertTrue(audio.media.isEmpty)
        XCTAssertEqual(audio.id, UUID(uuidString: "10000000-0000-0000-0000-000000000010"))
        XCTAssertEqual(notti.id, UUID(uuidString: "10000000-0000-0000-0000-000000000011"))
    }

    func testRecordsStateSurvivesSiblingAndDetailRoundTrips() throws {
        let state = makeState()
        state.select(.records)
        state.selectedRecordsFilter = .audio
        state.recordsSearchQuery = "语音"
        let recordID = try XCTUnwrap(state.filteredRecordFixtures.first?.id)

        state.openRecord(recordID, origin: .records)
        state.dismissOverlay()
        state.select(.today)
        state.select(.records)

        XCTAssertEqual(state.destination, .records)
        XCTAssertEqual(state.selectedRecordsFilter, .audio)
        XCTAssertEqual(state.recordsSearchQuery, "语音")
        XCTAssertEqual(state.filteredRecordFixtures.map(\.id), [recordID])
    }

    func testOverlayRoutingUsesKnownFixturesAndCanDismiss() throws {
        let state = makeState()
        let recordID = try XCTUnwrap(state.recordFixtures.first?.id)

        state.openRecord(recordID, origin: .records)
        XCTAssertEqual(state.overlay, .recordDetail(recordID: recordID, origin: .records))

        state.openModule(.todos)
        XCTAssertEqual(state.overlay, .module(.todos))

        state.dismissOverlay()
        XCTAssertNil(state.overlay)

        state.openRecord(
            UUID(uuidString: "99999999-0000-0000-0000-000000000001")!,
            origin: .today
        )
        XCTAssertNil(state.overlay)
    }

    private func makeState(scenario: NewUIPreviewScenario = .calm) -> NewUIPreviewState {
        NewUIPreviewState(scenario: scenario, startsContextTimer: false)
    }
}
