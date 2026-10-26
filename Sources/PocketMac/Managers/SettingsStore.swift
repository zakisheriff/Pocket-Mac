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

@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("pocketmac.layoutMode") var layoutModeRaw: String = LayoutMode.direct.rawValue
    @AppStorage("pocketmac.pointerSensitivity") var pointerSensitivity: Double = 1.6
    @AppStorage("pocketmac.reverseScrolling") var reverseScrolling: Bool = false
    @AppStorage("pocketmac.pointerSize") var pointerSize: Double = 26

    var layoutMode: LayoutMode {
        get { LayoutMode(rawValue: layoutModeRaw) ?? .direct }
        set { layoutModeRaw = newValue.rawValue }
    }
}
