import SwiftUI

/// Original gradient wallpapers (no copyrighted Apple artwork) in the spirit
/// of macOS's default desktop pictures.
enum WallpaperOption: String, CaseIterable, Identifiable {
    case sonomaDusk
    case montereyWave
    case bigSurGlow
    case venturaHorizon
    case graphiteMono
    case mojaveDune

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sonomaDusk: return "Dusk"
        case .montereyWave: return "Wave"
        case .bigSurGlow: return "Glow"
        case .venturaHorizon: return "Horizon"
        case .graphiteMono: return "Graphite"
        case .mojaveDune: return "Dune"
        }
    }

    var colors: [Color] {
        switch self {
        case .sonomaDusk:
            return [Color(red: 0.98, green: 0.55, blue: 0.36), Color(red: 0.55, green: 0.24, blue: 0.62), Color(red: 0.11, green: 0.14, blue: 0.38)]
        case .montereyWave:
            return [Color(red: 0.16, green: 0.55, blue: 0.86), Color(red: 0.08, green: 0.27, blue: 0.56), Color(red: 0.02, green: 0.07, blue: 0.22)]
        case .bigSurGlow:
            return [Color(red: 0.99, green: 0.78, blue: 0.35), Color(red: 0.93, green: 0.44, blue: 0.38), Color(red: 0.42, green: 0.14, blue: 0.42)]
        case .venturaHorizon:
            return [Color(red: 0.30, green: 0.75, blue: 0.70), Color(red: 0.14, green: 0.42, blue: 0.55), Color(red: 0.05, green: 0.12, blue: 0.28)]
        case .graphiteMono:
            return [Color(white: 0.55), Color(white: 0.28), Color(white: 0.08)]
        case .mojaveDune:
            return [Color(red: 0.93, green: 0.62, blue: 0.35), Color(red: 0.65, green: 0.33, blue: 0.22), Color(red: 0.20, green: 0.11, blue: 0.12)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
