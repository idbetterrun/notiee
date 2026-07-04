import XCTest
@testable import Notiee

final class CuratedModelCatalogTests: XCTestCase {

    // MARK: - 目录数据

    func testCatalogPartitionsFiveTextAndThreeVision() {
        XCTAssertEqual(CuratedModelCatalog.models(kind: .text).count, 5)
        XCTAssertEqual(CuratedModelCatalog.models(kind: .vision).count, 3)
    }

    func testModelIDsMatchBackendCatalogVerbatim() {
        let textIDs = Set(CuratedModelCatalog.models(kind: .text).map(\.id))
        XCTAssertEqual(textIDs, [
            "deepseek-v4-flash", "deepseek-v4-pro",
            "MiniMax-M3", "MiniMax-M2.7-highspeed", "MiniMax-M2.7",
        ])
        let visionIDs = Set(CuratedModelCatalog.models(kind: .vision).map(\.id))
        XCTAssertEqual(visionIDs, [
            "doubao-seed-2-0-mini", "doubao-seed-2-0-lite", "doubao-seed-2-1-pro",
        ])
    }

    func testExactlyOneFreeModelPerKind() {
        XCTAssertEqual(
            CuratedModelCatalog.models(kind: .text).filter { $0.tier == .free }.map(\.id),
            ["deepseek-v4-flash"])
        XCTAssertEqual(
            CuratedModelCatalog.models(kind: .vision).filter { $0.tier == .free }.map(\.id),
            ["doubao-seed-2-0-mini"])
    }

    // MARK: - 查找容错

    func testModelLookupReturnsNilForUnknownID() {
        XCTAssertNil(CuratedModelCatalog.model(id: "gpt-9-ultra"))
    }

    func testModelLookupFindsKnownID() {
        XCTAssertEqual(CuratedModelCatalog.model(id: "MiniMax-M3")?.tier, .pro)
    }

    // MARK: - 档位放行

    func testFreeTierAllowsOnlyFreeModels() {
        let flash = CuratedModelCatalog.model(id: "deepseek-v4-flash")!
        let m3 = CuratedModelCatalog.model(id: "MiniMax-M3")!
        XCTAssertTrue(CuratedModelCatalog.isAllowed(flash, for: .free))
        XCTAssertFalse(CuratedModelCatalog.isAllowed(m3, for: .free))
    }

    func testProTierAllowsAllModels() {
        let m3 = CuratedModelCatalog.model(id: "MiniMax-M3")!
        XCTAssertTrue(CuratedModelCatalog.isAllowed(m3, for: .pro))
    }

    func testDefaultModelIsTheFreeModelPerKind() {
        XCTAssertEqual(CuratedModelCatalog.defaultModel(kind: .text, for: .free).id, "deepseek-v4-flash")
        XCTAssertEqual(CuratedModelCatalog.defaultModel(kind: .vision, for: .free).id, "doubao-seed-2-0-mini")
    }
}

final class CuratedModelSelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "curated-selection-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testUnsetSelectionFallsBackToFreeDefault() {
        let sel = CuratedModelSelection(defaults: defaults)
        XCTAssertEqual(sel.textModelID(for: .free), "deepseek-v4-flash")
        XCTAssertEqual(sel.visionModelID(for: .free), "doubao-seed-2-0-mini")
    }

    func testFreeTierClampsStoredProModelToDefault() {
        let sel = CuratedModelSelection(defaults: defaults)
        sel.setTextModel("MiniMax-M3")
        XCTAssertEqual(sel.textModelID(for: .free), "deepseek-v4-flash")
    }

    func testProTierHonorsStoredProModel() {
        let sel = CuratedModelSelection(defaults: defaults)
        sel.setTextModel("MiniMax-M3")
        XCTAssertEqual(sel.textModelID(for: .pro), "MiniMax-M3")
    }

    func testUnknownStoredModelFallsBackToDefault() {
        let sel = CuratedModelSelection(defaults: defaults)
        sel.setTextModel("does-not-exist")
        XCTAssertEqual(sel.textModelID(for: .pro), "deepseek-v4-flash")
    }

    func testWrongKindStoredModelFallsBackToDefault() {
        let sel = CuratedModelSelection(defaults: defaults)
        sel.setTextModel("doubao-seed-2-0-mini")
        XCTAssertEqual(sel.textModelID(for: .pro), "deepseek-v4-flash")
    }
}
