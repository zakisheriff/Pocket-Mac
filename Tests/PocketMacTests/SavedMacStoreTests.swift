import XCTest
@testable import Pocket_Mac

@MainActor
final class SavedMacStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SavedMacStoreTests")
        defaults.removePersistentDomain(forName: "SavedMacStoreTests")
    }

    func testRememberedPasswordIsThereNextTime() {
        let store = SavedMacStore(defaults: defaults)
        let mac = store.save(name: "Test Mac", address: .bonjour(serviceName: "Test Mac"), username: "tester", password: "test-pw")
        defer { store.remove(mac) }

        XCTAssertEqual(store.password(for: mac), "test-pw")
        let reopened = SavedMacStore(defaults: defaults)
        XCTAssertEqual(reopened.macs.first.flatMap(reopened.password(for:)), "test-pw")
    }
}
