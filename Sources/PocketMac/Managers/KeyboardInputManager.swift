import SwiftUI
import Combine

/// Routes key presses from the simulated Mac keyboard to whichever text
/// buffer currently has focus (Notes body, Safari address bar, Spotlight,
/// Terminal, …), without relying on the real system keyboard/responder chain.
@MainActor
final class KeyboardInputManager: ObservableObject {

    enum Target: Equatable {
        case none
        case notes
        case safariAddressBar
        case spotlight
        case terminal
    }

    @Published var target: Target = .none
    @Published var isShiftOn = false
    @Published var isCapsLockOn = false

    /// Fired for every resolved keystroke; views subscribe and apply it to
    /// their own bound text instead of the manager owning every string.
    let keyPressed = PassthroughSubject<KeyAction, Never>()

    enum KeyAction: Equatable {
        case character(String)
        case backspace
        case `return`
        case tab
        case escape
    }

    func press(_ raw: String) {
        let char = (isShiftOn || isCapsLockOn) ? raw.uppercased() : raw.lowercased()
        keyPressed.send(.character(char))
        if isShiftOn { isShiftOn = false }
        HapticsManager.tap()
    }

    func pressBackspace() {
        keyPressed.send(.backspace)
        HapticsManager.tap()
    }

    func pressReturn() {
        keyPressed.send(.return)
        HapticsManager.tap()
    }

    func pressTab() {
        keyPressed.send(.tab)
        HapticsManager.tap()
    }

    func pressEscape() {
        keyPressed.send(.escape)
        target = .none
        HapticsManager.tap()
    }

    func toggleShift() {
        isShiftOn.toggle()
        HapticsManager.selectionChanged()
    }

    func toggleCapsLock() {
        isCapsLockOn.toggle()
        HapticsManager.selectionChanged()
    }
}
