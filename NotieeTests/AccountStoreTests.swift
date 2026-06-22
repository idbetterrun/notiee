import XCTest
@testable import Notiee

@MainActor
final class AccountStoreTests: XCTestCase {
    private func makeStore() -> AccountStore {
        let ud = UserDefaults(suiteName: "test.account.\(UUID().uuidString)")!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return AccountStore(userDefaults: ud, avatarDirectory: dir)
    }

    func testInitiallyLoggedOut() {
        XCTAssertFalse(makeStore().isLoggedIn)
    }

    func testLocalLogin_setsProfileAndPersists() {
        let store = makeStore()
        store.localLogin(name: "  Lany  ")
        XCTAssertTrue(store.isLoggedIn)
        XCTAssertEqual(store.profile?.displayName, "Lany")          // 去空格
        XCTAssertEqual(store.profile?.loginMethod, .local)
    }

    func testUpdateName() {
        let store = makeStore()
        store.localLogin(name: "A")
        store.updateName("小明")
        XCTAssertEqual(store.profile?.displayName, "小明")
    }

    func testLogout_clears() {
        let store = makeStore()
        store.localLogin(name: "A")
        store.logout()
        XCTAssertFalse(store.isLoggedIn)
        XCTAssertNil(store.profile)
    }

    func testPersistenceAcrossInstances() {
        let ud = UserDefaults(suiteName: "test.account.persist.\(UUID().uuidString)")!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = AccountStore(userDefaults: ud, avatarDirectory: dir)
        a.localLogin(name: "Persisted")
        let b = AccountStore(userDefaults: ud, avatarDirectory: dir)
        XCTAssertEqual(b.profile?.displayName, "Persisted")
    }

    func testGreeting_byHour() {
        func g(_ hour: Int) -> String {
            var c = DateComponents(); c.year = 2026; c.month = 6; c.day = 21; c.hour = hour
            let d = Calendar(identifier: .gregorian).date(from: c)!
            return AccountStore.greeting(at: d, calendar: Calendar(identifier: .gregorian))
        }
        // greeting() returns a localized string (Text(greeting()) won't auto-localize a
        // runtime String), so assert against the localized form of each expected key. This
        // verifies the hour→bucket mapping independent of the test host's active language.
        XCTAssertEqual(g(2), String(localized: "凌晨好"))
        XCTAssertEqual(g(6), String(localized: "早上好"))
        XCTAssertEqual(g(9), String(localized: "上午好"))
        XCTAssertEqual(g(12), String(localized: "中午好"))
        XCTAssertEqual(g(15), String(localized: "下午好"))
        XCTAssertEqual(g(20), String(localized: "晚上好"))
        XCTAssertEqual(g(23), String(localized: "深夜好"))
    }
}
