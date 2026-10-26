import SwiftUI

/// A key on the on-screen Mac keyboard.
struct MacKey: Identifiable, Hashable {
    enum Action: Hashable {
        case character(Character, shifted: Character)
        case keysym(UInt32)
        case modifier(ModifierKey)
        case capsLock
        /// MacBook-style stacked half-height ↑ and ↓.
        case verticalArrows
    }

    let id: String
    let label: String
    let action: Action
    /// Relative width; a letter key is 1.
    let width: CGFloat

    static func char(_ base: Character, _ shifted: Character? = nil, width: CGFloat = 1) -> MacKey {
        let shifted = shifted ?? Character(String(base).uppercased())
        return MacKey(id: "char-\(base)", label: String(base), action: .character(base, shifted: shifted), width: width)
    }

    static func special(_ id: String, _ label: String, _ keysym: UInt32, width: CGFloat) -> MacKey {
        MacKey(id: id, label: label, action: .keysym(keysym), width: width)
    }

    static func modifier(_ modifier: ModifierKey, id: String, label: String, width: CGFloat) -> MacKey {
        MacKey(id: id, label: label, action: .modifier(modifier), width: width)
    }

    /// US Mac layout, every row 14.5 units wide.
    static let rows: [[MacKey]] = [
        [.char("`", "~"), .char("1", "!"), .char("2", "@"), .char("3", "#"), .char("4", "$"), .char("5", "%"),
         .char("6", "^"), .char("7", "&"), .char("8", "*"), .char("9", "("), .char("0", ")"), .char("-", "_"),
         .char("=", "+"), .special("delete", "⌫", Keysym.backspace, width: 1.5)],
        [.special("tab", "tab", Keysym.tab, width: 1.5), .char("q"), .char("w"), .char("e"), .char("r"), .char("t"),
         .char("y"), .char("u"), .char("i"), .char("o"), .char("p"), .char("[", "{"), .char("]", "}"), .char("\\", "|")],
        [MacKey(id: "caps", label: "caps", action: .capsLock, width: 1.75), .char("a"), .char("s"), .char("d"),
         .char("f"), .char("g"), .char("h"), .char("j"), .char("k"), .char("l"), .char(";", ":"), .char("'", "\""),
         .special("return", "return", Keysym.returnKey, width: 1.75)],
        [.modifier(.shift, id: "shift-left", label: "shift", width: 2.25), .char("z"), .char("x"), .char("c"),
         .char("v"), .char("b"), .char("n"), .char("m"), .char(",", "<"), .char(".", ">"), .char("/", "?"),
         .modifier(.shift, id: "shift-right", label: "shift", width: 2.25)],
        [.special("esc", "esc", Keysym.escape, width: 1), .modifier(.control, id: "control", label: "⌃", width: 1),
         .modifier(.option, id: "option-left", label: "⌥", width: 1), .modifier(.command, id: "command-left", label: "⌘", width: 1.5),
         MacKey(id: "space", label: "", action: .character(" ", shifted: " "), width: 4.5),
         .modifier(.command, id: "command-right", label: "⌘", width: 1.5), .modifier(.option, id: "option-right", label: "⌥", width: 1),
         .special("left", "←", Keysym.left, width: 1), MacKey(id: "updown", label: "", action: .verticalArrows, width: 1),
         .special("right", "→", Keysym.right, width: 1)],
    ]
}

/// Turns trackpad gestures and key taps into input for the Mac.
@MainActor
final class SessionInputController: ObservableObject {
    /// Modifiers applied to the next key or click, then released.
    @Published private(set) var latched: Set<ModifierKey> = []
    /// Modifiers held until tapped again (double-tap a modifier to lock it).
    @Published private(set) var locked: Set<ModifierKey> = []
    @Published private(set) var capsLock = false

    let client: RFBClient
    private let settings: SettingsStore
    private var scrollRemainder = CGVector.zero
    private var lastModifierTap: (ModifierKey, Date)?

    init(client: RFBClient, settings: SettingsStore) {
        self.client = client
        self.settings = settings
    }

    var activeModifiers: Set<ModifierKey> { latched.union(locked) }

    func isActive(_ modifier: ModifierKey) -> Bool { activeModifiers.contains(modifier) }

    var trackpadActions: TrackpadGestureHandler.Actions {
        var actions = TrackpadGestureHandler.Actions()
        actions.move = { [weak self] delta, speed in self?.movePointer(delta, speed: speed) }
        actions.click = { [weak self] in self?.click(.left) }
        actions.rightClick = { [weak self] in self?.click(.right) }
        actions.scroll = { [weak self] delta in self?.scroll(delta) }
        actions.swipe = { [weak self] delta in self?.scroll(delta) }
        actions.point = { [weak self] point in self?.client.movePointer(to: point) }
        actions.dragBegan = { [weak self] in self?.client.press(.left) }
        actions.dragEnded = { [weak self] in self?.client.release(.left) }
        return actions
    }

    // MARK: Pointer

    private func movePointer(_ delta: CGVector, speed: CGFloat) {
        let acceleration = 1 + min(speed / 1800, 1.5)
        let factor = CGFloat(settings.pointerSensitivity) * 0.6 * acceleration
        client.movePointer(by: CGVector(dx: delta.dx * factor, dy: delta.dy * factor))
    }

    private func click(_ button: RFBButtons) {
        client.click(button, modifiers: activeModifiers)
        latched.removeAll()
    }

    private func scroll(_ delta: CGVector) {
        let step: CGFloat = 12
        let direction: CGFloat = settings.reverseScrolling ? -1 : 1
        scrollRemainder.dx += delta.dx * direction
        scrollRemainder.dy += delta.dy * direction
        let vertical = Int(scrollRemainder.dy / step)
        let horizontal = Int(scrollRemainder.dx / step)
        guard vertical != 0 || horizontal != 0 else { return }
        scrollRemainder.dy -= CGFloat(vertical) * step
        scrollRemainder.dx -= CGFloat(horizontal) * step
        client.scroll(vertical: vertical, horizontal: horizontal)
    }

    // MARK: Keyboard

    func press(_ key: MacKey) {
        HapticsManager.tap()
        switch key.action {
        case .modifier(let modifier):
            toggle(modifier)
        case .capsLock:
            capsLock.toggle()
        case .verticalArrows:
            break // each half sends its own arrow via tapKeysym
        case .keysym(let keysym):
            client.tapKey(keysym, modifiers: activeModifiers)
            latched.removeAll()
        case .character(let base, let shifted):
            let shiftOn = isActive(.shift)
            var character = shiftOn ? shifted : base
            if capsLock, !shiftOn, base.isLetter { character = shifted }
            if let keysym = Keysym.character(character) {
                client.tapKey(keysym, modifiers: activeModifiers)
            }
            latched.removeAll()
        }
    }

    func tapKeysym(_ keysym: UInt32, modifiers: Set<ModifierKey> = []) {
        HapticsManager.tap()
        client.tapKey(keysym, modifiers: modifiers.union(activeModifiers))
        latched.removeAll()
    }

    func label(for key: MacKey) -> String {
        guard case .character(let base, let shifted) = key.action else { return key.label }
        if isActive(.shift) || (capsLock && base.isLetter) { return String(shifted) }
        return key.label
    }

    private func toggle(_ modifier: ModifierKey) {
        if locked.contains(modifier) {
            locked.remove(modifier)
            latched.remove(modifier)
        } else if let (last, time) = lastModifierTap, last == modifier, Date().timeIntervalSince(time) < 0.35 {
            latched.remove(modifier)
            locked.insert(modifier)
        } else if latched.contains(modifier) {
            latched.remove(modifier)
        } else {
            latched.insert(modifier)
        }
        lastModifierTap = (modifier, Date())
    }
}
