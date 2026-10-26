import XCTest
import SwiftUI
@testable import Pocket_Mac

@MainActor
final class CursorManagerTests: XCTestCase {

    func testCursorStartsCenteredInItsBounds() {
        let cursor = CursorManager()
        cursor.setBounds(CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertEqual(cursor.position, CGPoint(x: 100, y: 50))
    }

    func testApplyingADeltaMovesTheCursorBySensitivity() {
        let cursor = CursorManager()
        cursor.sensitivity = 2
        cursor.setBounds(CGRect(x: 0, y: 0, width: 1000, height: 1000))
        let start = cursor.position
        cursor.applyDelta(CGSize(width: 10, height: -5))
        XCTAssertEqual(cursor.position.x, start.x + 20, accuracy: 0.001)
        XCTAssertEqual(cursor.position.y, start.y - 10, accuracy: 0.001)
    }

    func testCursorCannotLeaveItsBounds() {
        let cursor = CursorManager()
        cursor.setBounds(CGRect(x: 0, y: 0, width: 50, height: 50))
        cursor.applyDelta(CGSize(width: 10_000, height: 10_000))
        XCTAssertEqual(cursor.position.x, 50, accuracy: 0.001)
        XCTAssertEqual(cursor.position.y, 50, accuracy: 0.001)

        cursor.applyDelta(CGSize(width: -10_000, height: -10_000))
        XCTAssertEqual(cursor.position.x, 0, accuracy: 0.001)
        XCTAssertEqual(cursor.position.y, 0, accuracy: 0.001)
    }

    func testJumpMovesDirectlyAndStillClamps() {
        let cursor = CursorManager()
        cursor.setBounds(CGRect(x: 0, y: 0, width: 100, height: 100))
        cursor.jump(to: CGPoint(x: 500, y: -500))
        XCTAssertEqual(cursor.position, CGPoint(x: 100, y: 0))
    }
}
