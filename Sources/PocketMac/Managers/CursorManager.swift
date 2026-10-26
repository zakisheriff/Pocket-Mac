import SwiftUI

/// Drives the on-screen cursor: trackpad-relative tracking in Duo mode,
/// and an optional floating cursor in Direct mode.
@MainActor
final class CursorManager: ObservableObject {
    @Published var position: CGPoint
    @Published var isPressed = false
    @Published var isVisible = false

    /// How many desktop points the cursor moves per point the finger drags.
    /// Mirrors a real trackpad's acceleration feel.
    var sensitivity: CGFloat = 1.6

    private(set) var bounds: CGRect = .zero

    init(initialPosition: CGPoint = .zero) {
        position = initialPosition
    }

    func setBounds(_ rect: CGRect) {
        bounds = rect
        if position == .zero {
            position = CGPoint(x: rect.midX, y: rect.midY)
        } else {
            clamp()
        }
    }

    func applyDelta(_ delta: CGSize) {
        position.x += delta.width * sensitivity
        position.y += delta.height * sensitivity
        clamp()
    }

    func jump(to point: CGPoint) {
        position = point
        clamp()
    }

    private func clamp() {
        guard bounds != .zero else { return }
        position.x = min(max(position.x, bounds.minX), bounds.maxX)
        position.y = min(max(position.y, bounds.minY), bounds.maxY)
    }
}
