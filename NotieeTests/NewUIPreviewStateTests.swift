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

    func testOverlayRoutingUsesKnownFixturesAndCanDismiss() throws {
        let state = makeState()
        let recordID = try XCTUnwrap(state.recordFixtures.first?.id)

        state.openRecord(recordID)
        XCTAssertEqual(state.overlay, .recordDetail(recordID))

        state.openModule(.todos)
        XCTAssertEqual(state.overlay, .module(.todos))

        state.dismissOverlay()
        XCTAssertNil(state.overlay)

        state.openRecord(UUID(uuidString: "99999999-0000-0000-0000-000000000001")!)
        XCTAssertNil(state.overlay)
    }

    private func makeState(scenario: NewUIPreviewScenario = .calm) -> NewUIPreviewState {
        NewUIPreviewState(scenario: scenario, startsContextTimer: false)
    }
}
