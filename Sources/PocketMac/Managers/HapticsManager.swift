import UIKit

/// Centralised haptic feedback so every tap, click and key press in the
/// simulated desktop feels tactile, the way a real trackpad click does.
enum HapticsManager {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()

    static func prepare() {
        light.prepare()
        medium.prepare()
        rigid.prepare()
        selection.prepare()
    }

    /// A trackpad tap or on-screen key press.
    static func tap() {
        light.impactOccurred()
    }

    /// A trackpad "click" (firmer, like a real Force Touch trackpad).
    static func click() {
        rigid.impactOccurred(intensity: 0.8)
    }

    /// Opening an app, snapping a window into place.
    static func appOpen() {
        medium.impactOccurred()
    }

    /// Dragging across dock icons / menu items.
    static func selectionChanged() {
        selection.selectionChanged()
    }
}
