import XCTest
import Combine
@testable import Pocket_Mac

@MainActor
final class KeyboardInputManagerTests: XCTestCase {

    func testPressingALetterSendsItLowercasedByDefault() {
        let keyboard = KeyboardInputManager()
        var received: [KeyboardInputManager.KeyAction] = []
        let cancellable = keyboard.keyPressed.sink { received.append($0) }
        defer { cancellable.cancel() }

        keyboard.press("A")

        XCTAssertEqual(received, [.character("a")])
    }

    func testShiftUppercasesTheNextKeyThenResetsItself() {
        let keyboard = KeyboardInputManager()
        var received: [KeyboardInputManager.KeyAction] = []
        let cancellable = keyboard.keyPressed.sink { received.append($0) }
        defer { cancellable.cancel() }

        keyboard.toggleShift()
        XCTAssertTrue(keyboard.isShiftOn)

        keyboard.press("a")
        XCTAssertEqual(received, [.character("A")])
        XCTAssertFalse(keyboard.isShiftOn, "Shift should release after one keystroke, like a real keyboard")
    }

    func testCapsLockKeepsUppercasingUntilToggledOff() {
        let keyboard = KeyboardInputManager()
        var received: [KeyboardInputManager.KeyAction] = []
        let cancellable = keyboard.keyPressed.sink { received.append($0) }
        defer { cancellable.cancel() }

        keyboard.toggleCapsLock()
        keyboard.press("a")
        keyboard.press("b")

        XCTAssertEqual(received, [.character("A"), .character("B")])
    }

    func testEscapeClearsTheFocusedTarget() {
        let keyboard = KeyboardInputManager()
        keyboard.target = .notes
        keyboard.pressEscape()
        XCTAssertEqual(keyboard.target, .none)
    }
}
