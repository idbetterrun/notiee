import XCTest
@testable import Notiee

@MainActor
final class EntitlementStoreTests: XCTestCase {

    func testStartsWithNoQuotaAndFreeTier() {
        let store = EntitlementStore()
        XCTAssertNil(store.quota)
        XCTAssertEqual(store.tier, .free)
    }

    func testQuotaUpdatesFromBroadcast() {
        let store = EntitlementStore()
        let q = BackendQuota(tier: "pro", used: 12, limit: 300, remaining: 288)
        q.broadcast()

        let exp = expectation(description: "quota updated on main")
        DispatchQueue.main.async {
            XCTAssertEqual(store.quota, q)
            XCTAssertEqual(store.tier, .pro)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
    }
}
