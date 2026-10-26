import Foundation

/// X11 keysyms, which is how VNC names keys on the wire. macOS Screen
/// Sharing maps Alt → Option and Super → Command.
enum Keysym {
    static let backspace: UInt32 = 0xff08
    static let tab: UInt32 = 0xff09
    static let returnKey: UInt32 = 0xff0d
    static let escape: UInt32 = 0xff1b
    static let home: UInt32 = 0xff50
    static let left: UInt32 = 0xff51
    static let up: UInt32 = 0xff52
    static let right: UInt32 = 0xff53
    static let down: UInt32 = 0xff54
    static let pageUp: UInt32 = 0xff55
    static let pageDown: UInt32 = 0xff56
    static let end: UInt32 = 0xff57
    static let forwardDelete: UInt32 = 0xffff
    static let shift: UInt32 = 0xffe1
    static let control: UInt32 = 0xffe3
    static let capsLock: UInt32 = 0xffe5
    static let option: UInt32 = 0xffe9
    static let command: UInt32 = 0xffeb

    static func function(_ number: Int) -> UInt32 {
        precondition((1...12).contains(number))
        return 0xffbe + UInt32(number - 1)
    }

    /// Printable characters: Latin-1 keysyms equal their code point, anything
    /// else uses the Unicode keysym range.
    static func character(_ character: Character) -> UInt32? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        if scalar == "\n" || scalar == "\r" { return returnKey }
        if scalar == "\t" { return tab }
        if scalar.value >= 0x20 && scalar.value <= 0x7e { return scalar.value }
        if scalar.value >= 0xa0 && scalar.value <= 0xff { return scalar.value }
        if scalar.value > 0xff { return 0x0100_0000 | scalar.value }
        return nil
    }
}

/// Modifier keys the on-screen keyboard can latch.
enum ModifierKey: CaseIterable, Hashable {
    case shift, control, option, command

    var keysym: UInt32 {
        switch self {
        case .shift: return Keysym.shift
        case .control: return Keysym.control
        case .option: return Keysym.option
        case .command: return Keysym.command
        }
    }

    var symbol: String {
        switch self {
        case .shift: return "⇧"
        case .control: return "⌃"
        case .option: return "⌥"
        case .command: return "⌘"
        }
    }
}
