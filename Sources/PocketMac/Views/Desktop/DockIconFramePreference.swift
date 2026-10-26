import SwiftUI

/// Collects each dock icon's frame (in the shared "pocketMacDesktop"
/// coordinate space) so indirect trackpad clicks can hit-test the dock.
struct DockIconFramePreferenceKey: PreferenceKey {
    static var defaultValue: [AppKind: CGRect] = [:]

    static func reduce(value: inout [AppKind: CGRect], nextValue: () -> [AppKind: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct LaunchpadButtonFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Name of the coordinate space shared by the desktop canvas, its windows,
/// the cursor and the dock, so trackpad hit-testing lines up everywhere.
enum DesktopCoordinateSpace {
    static let name = "pocketMacDesktop"
}
