import SwiftUI

/// How the remote Mac session is laid out on the phone.
enum LayoutMode: String, CaseIterable, Identifiable {
    /// Regular iPhones (17, 17 Pro, 17 Pro Max…): the Mac's screen fills the
    /// display and the whole screen works as a trackpad, with the keyboard
    /// shown on demand.
    case direct

    /// Foldable "iPhone Duo" style: in landscape the top half shows the Mac's
    /// screen and the bottom half is a fixed keyboard + trackpad deck.
    case duo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .direct: return "iPhone"
        case .duo: return "iPhone Duo (laptop split)"
        }
    }
}

/// How touches on the Mac's screen control it.
enum InputMode: String, CaseIterable, Identifiable {
    /// The screen is a trackpad moving a pointer, like a MacBook.
    case trackpad
    /// No pointer: tap exactly what you want, like a touchscreen Mac.
    case touch

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trackpad: return "Trackpad"
        case .touch: return "Touch"
        }
    }
}

/// How the phone draws the pointer over the Mac's screen.
enum PointerStyle: String, CaseIterable, Identifiable {
    case macArrow, whiteArrow, ring, dot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .macArrow: return "Mac Arrow"
        case .whiteArrow: return "White Arrow"
        case .ring: return "Ring"
        case .dot: return "Dot"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("pocketmac.layoutMode") var layoutModeRaw: String = LayoutMode.direct.rawValue
    @AppStorage("pocketmac.pointerSensitivity") var pointerSensitivity: Double = 1.6
    @AppStorage("pocketmac.reverseScrolling") var reverseScrolling: Bool = false
    @AppStorage("pocketmac.pointerSize") var pointerSize: Double = 24
    @AppStorage("pocketmac.pointerStyle") var pointerStyleRaw: String = PointerStyle.macArrow.rawValue
    @AppStorage("pocketmac.inputMode") var inputModeRaw: String = InputMode.trackpad.rawValue

    @AppStorage("pocketmac.streamMode") var streamModeRaw: String = RFBStreamMode.responsive.rawValue

    var streamMode: RFBStreamMode {
        get { RFBStreamMode(rawValue: streamModeRaw) ?? .responsive }
        set { streamModeRaw = newValue.rawValue }
    }

    var inputMode: InputMode {
        get { InputMode(rawValue: inputModeRaw) ?? .trackpad }
        set { inputModeRaw = newValue.rawValue }
    }

    var pointerStyle: PointerStyle {
        get { PointerStyle(rawValue: pointerStyleRaw) ?? .macArrow }
        set { pointerStyleRaw = newValue.rawValue }
    }

    var layoutMode: LayoutMode {
        get { LayoutMode(rawValue: layoutModeRaw) ?? .direct }
        set { layoutModeRaw = newValue.rawValue }
    }
}
