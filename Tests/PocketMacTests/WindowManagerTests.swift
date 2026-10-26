import XCTest
import SwiftUI
@testable import Pocket_Mac

@MainActor
final class WindowManagerTests: XCTestCase {

    private func makeManager() -> WindowManager {
        let manager = WindowManager()
        manager.canvasBounds = CGRect(x: 0, y: 0, width: 400, height: 500)
        return manager
    }

    func testOpeningAnAppCreatesExactlyOneWindow() {
        let manager = makeManager()
        manager.open(.notes)
        XCTAssertEqual(manager.windows.count, 1)
        XCTAssertEqual(manager.windows.first?.kind, .notes)
    }

    func testOpeningTheSameAppTwiceDoesNotDuplicateItsWindow() {
        let manager = makeManager()
        manager.open(.finder)
        manager.open(.finder)
        XCTAssertEqual(manager.windows.count, 1)
    }

    func testClosingAWindowRemovesItFromOrder() {
        let manager = makeManager()
        manager.open(.calculator)
        let id = manager.windows[0].id
        manager.close(id)
        XCTAssertTrue(manager.windows.isEmpty)
        XCTAssertFalse(manager.order.contains(id))
    }

    func testBringingAWindowToFrontMakesItFrontmost() {
        let manager = makeManager()
        manager.open(.finder)
        manager.open(.notes)
        let finderID = manager.windows.first(where: { $0.kind == .finder })!.id
        manager.bringToFront(finderID)
        XCTAssertEqual(manager.frontmostWindow?.id, finderID)
    }

    func testMinimizingThenRestoringBringsItBackAndFrontmost() {
        let manager = makeManager()
        manager.open(.notes)
        let id = manager.windows[0].id
        manager.minimize(id)
        XCTAssertTrue(manager.windows[0].isMinimized)
        manager.restore(id)
        XCTAssertFalse(manager.windows[0].isMinimized)
        XCTAssertEqual(manager.frontmostWindow?.id, id)
    }

    func testNewWindowsAreSizedWithinTheCanvasBounds() {
        let manager = makeManager()
        manager.open(.safari) // default size (460x300) is wider than the 400pt canvas
        let window = manager.windows[0]
        XCTAssertLessThanOrEqual(window.size.width, manager.canvasBounds.width)
    }

    func testHitTestResolvesCloseButtonOnlyInsideItsSmallRegion() {
        let manager = makeManager()
        manager.open(.notes)
        let window = manager.windows[0]
        let closePoint = CGPoint(x: window.position.x + 16, y: window.position.y + 14)
        guard case .closeButton(let id) = manager.hitTest(closePoint) else {
            return XCTFail("Expected a close-button hit")
        }
        XCTAssertEqual(id, window.id)
    }
}
