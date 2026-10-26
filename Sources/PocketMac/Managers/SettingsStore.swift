import SwiftUI

/// Which physical layout Pocket Mac should simulate.
enum LayoutMode: String, CaseIterable, Identifiable {
    /// A regular, non-folding iPhone (17, 17 Pro, 17 Pro Max, …): a single
    /// flat screen showing the full desktop, driven by direct touch with an
    /// optional floating trackpad/keyboard overlay.
    case direct

    /// The fictional "iPhone Duo": the screen splits in landscape into a
    /// desktop half and a physical trackpad + keyboard deck, like folding a
    /// laptop shut.
    case duo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .direct: return "iPhone (no fold)"
        case .duo: return "iPhone Duo (fold simulation)"
        }
    }
}

/// Persisted user preferences, shared across the whole app.
@MainActor
final class SettingsStore: ObservableObject {
    @AppStorage("pocketmac.layoutMode") var layoutModeRaw: String = LayoutMode.direct.rawValue
    @AppStorage("pocketmac.wallpaper") var wallpaperRaw: String = WallpaperOption.sonomaDusk.rawValue
    @AppStorage("pocketmac.trackpadOverlayEnabled") var trackpadOverlayEnabled: Bool = false
    @AppStorage("pocketmac.pointerSensitivity") var pointerSensitivity: Double = 1.6
    @AppStorage("pocketmac.hasOnboarded") var hasOnboarded: Bool = false

    var layoutMode: LayoutMode {
        get { LayoutMode(rawValue: layoutModeRaw) ?? .direct }
        set { layoutModeRaw = newValue.rawValue }
    }

    var wallpaper: WallpaperOption {
        get { WallpaperOption(rawValue: wallpaperRaw) ?? .sonomaDusk }
        set { wallpaperRaw = newValue.rawValue }
    }
}
