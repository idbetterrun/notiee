import XCTest
@testable import Notiee

final class CurrentEntitlementTests: XCTestCase {
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "entitlement-\(UUID().uuidString)"
        CurrentEntitlement.defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        CurrentEntitlement.defaults.removePersistentDomain(forName: suite)
        CurrentEntitlement.defaults = .standard
        suite = nil
        super.tearDown()
    }

    func testDefaultsToFree() {
        XCTAssertEqual(CurrentEntitlement.tier, .free)
    }

    func testPersistsPro() {
        CurrentEntitlement.tier = .pro
        XCTAssertEqual(CurrentEntitlement.tier, .pro)
        XCTAssertEqual(CurrentEntitlement.defaults.string(forKey: UDK.entitlementTier), "pro")
    }

    func testUnknownRawFallsBackToFree() {
        CurrentEntitlement.defaults.set("enterprise", forKey: UDK.entitlementTier)
        XCTAssertEqual(CurrentEntitlement.tier, .free)
    }
}
