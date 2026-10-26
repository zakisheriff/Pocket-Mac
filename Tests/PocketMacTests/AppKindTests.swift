import XCTest
@testable import Pocket_Mac

final class AppKindTests: XCTestCase {

    func testEveryAppKindHasAPositiveDefaultSize() {
        for kind in AppKind.allCases {
            XCTAssertGreaterThan(kind.defaultSize.width, 0, "\(kind) has no width")
            XCTAssertGreaterThan(kind.defaultSize.height, 0, "\(kind) has no height")
        }
    }

    func testDockAppsExcludesNothingUnexpectedAndHasNoDuplicates() {
        let dockApps = AppKind.dockApps
        XCTAssertEqual(Set(dockApps).count, dockApps.count, "Dock should not list the same app twice")
        XCTAssertFalse(dockApps.isEmpty)
    }

    func testEveryAppKindHasADisplayNameAndSymbol() {
        for kind in AppKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(kind.symbolName.isEmpty)
        }
    }
}
