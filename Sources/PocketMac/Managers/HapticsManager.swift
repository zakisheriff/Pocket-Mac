import UIKit

/// Every touch in Pocket Mac gets haptic feedback, routed through here.
enum HapticsManager {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let selection = UISelectionFeedbackGenerator()
    private static let notification = UINotificationFeedbackGenerator()

    static func prepare() {
        light.prepare()
        medium.prepare()
        rigid.prepare()
        selection.prepare()
        notification.prepare()
    }

    /// Key presses, secondary buttons, list rows.
    static func tap() {
        light.impactOccurred()
    }

    /// A trackpad click — firm, like a Force Touch trackpad.
    static func click() {
        rigid.impactOccurred(intensity: 0.8)
    }

    /// Primary actions, right-click, starting a drag.
    static func appOpen() {
        medium.impactOccurred()
    }

    static func selectionChanged() {
        selection.selectionChanged()
    }

    static func success() {
        notification.notificationOccurred(.success)
    }

    static func error() {
        notification.notificationOccurred(.error)
    }
}
