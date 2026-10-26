import SwiftUI

/// Every "app" that can run as a window inside the simulated desktop.
enum AppKind: String, CaseIterable, Identifiable {
    case finder
    case notes
    case safari
    case calculator
    case terminal
    case photos
    case settings
    case aboutThisMac
    case trash

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .finder: return "Finder"
        case .notes: return "Notes"
        case .safari: return "Safari"
        case .calculator: return "Calculator"
        case .terminal: return "Terminal"
        case .photos: return "Photos"
        case .settings: return "System Settings"
        case .aboutThisMac: return "About This Mac"
        case .trash: return "Trash"
        }
    }

    var symbolName: String {
        switch self {
        case .finder: return "face.smiling"
        case .notes: return "note.text"
        case .safari: return "safari.fill"
        case .calculator: return "plusminus.circle.fill"
        case .terminal: return "terminal.fill"
        case .photos: return "photo.stack.fill"
        case .settings: return "gearshape.fill"
        case .aboutThisMac: return "apple.logo"
        case .trash: return "trash.fill"
        }
    }

    var tint: Color {
        switch self {
        case .finder: return .blue
        case .notes: return .yellow
        case .safari: return .cyan
        case .calculator: return .gray
        case .terminal: return .black
        case .photos: return .pink
        case .settings: return .gray
        case .aboutThisMac: return .gray
        case .trash: return .gray
        }
    }

    /// Default size (in points, relative to a desktop canvas) for a freshly
    /// opened window of this kind.
    var defaultSize: CGSize {
        switch self {
        case .finder: return CGSize(width: 420, height: 280)
        case .notes: return CGSize(width: 320, height: 300)
        case .safari: return CGSize(width: 460, height: 300)
        case .calculator: return CGSize(width: 220, height: 300)
        case .terminal: return CGSize(width: 420, height: 260)
        case .photos: return CGSize(width: 380, height: 280)
        case .settings: return CGSize(width: 440, height: 320)
        case .aboutThisMac: return CGSize(width: 320, height: 260)
        case .trash: return CGSize(width: 360, height: 260)
        }
    }

    /// Apps pinned in the dock by default, left to right.
    static var dockApps: [AppKind] {
        [.finder, .safari, .notes, .photos, .calculator, .terminal, .settings, .trash]
    }
}
