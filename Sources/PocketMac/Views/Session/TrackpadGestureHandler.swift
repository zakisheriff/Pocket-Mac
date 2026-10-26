import UIKit

/// Turns touches on any UIView into Mac trackpad input: one finger moves
/// the pointer, tap clicks, two-finger tap right-clicks, two-finger drag
/// scrolls, press-and-hold then drag holds the button down, pinch zooms.
@MainActor
final class TrackpadGestureHandler: NSObject, UIGestureRecognizerDelegate {
    struct Actions {
        var move: (CGVector, _ speed: CGFloat) -> Void = { _, _ in }
        var click: () -> Void = {}
        var rightClick: () -> Void = {}
        var scroll: (CGVector) -> Void = { _ in }
        var dragBegan: () -> Void = {}
        var dragEnded: () -> Void = {}
        /// Scale change and the pinch centre in the view.
        var pinch: ((CGFloat, CGPoint) -> Void)?
    }

    var actions = Actions()
    /// Mac screen points per touch point, so a swipe across the surface
    /// covers the same share of the Mac screen whatever the zoom or size.
    var macPointsPerTouchPoint: () -> CGFloat = { 1 }
    private var lastDragLocation: CGPoint?

    private func scaled(_ x: CGFloat, _ y: CGFloat) -> CGVector {
        let factor = macPointsPerTouchPoint()
        return CGVector(dx: x * factor, dy: y * factor)
    }

    func attach(to view: UIView) {
        view.isMultipleTouchEnabled = true

        let rightTap = UITapGestureRecognizer(target: self, action: #selector(handleRightTap))
        rightTap.numberOfTouchesRequired = 2

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.numberOfTouchesRequired = 1

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        hold.minimumPressDuration = 0.3
        hold.allowableMovement = 12

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.require(toFail: hold)

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        scroll.delegate = self

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self

        for recognizer in [rightTap, tap, hold, pan, scroll, pinch] {
            view.addGestureRecognizer(recognizer)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer) ||
        (gestureRecognizer is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
    }

    @objc private func handleTap() {
        HapticsManager.click()
        actions.click()
    }

    @objc private func handleRightTap() {
        HapticsManager.appOpen()
        actions.rightClick()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let translation = recognizer.translation(in: view)
        let velocity = recognizer.velocity(in: view)
        recognizer.setTranslation(.zero, in: view)
        actions.move(scaled(translation.x, translation.y), hypot(velocity.x, velocity.y))
    }

    @objc private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let translation = recognizer.translation(in: view)
        recognizer.setTranslation(.zero, in: view)
        actions.scroll(CGVector(dx: translation.x, dy: translation.y))
    }

    @objc private func handleHold(_ recognizer: UILongPressGestureRecognizer) {
        guard let view = recognizer.view else { return }
        let location = recognizer.location(in: view)
        switch recognizer.state {
        case .began:
            lastDragLocation = location
            HapticsManager.appOpen()
            actions.dragBegan()
        case .changed:
            if let last = lastDragLocation {
                actions.move(scaled(location.x - last.x, location.y - last.y), 0)
            }
            lastDragLocation = location
        default:
            lastDragLocation = nil
            actions.dragEnded()
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let pinch = actions.pinch, let view = recognizer.view else { return }
        pinch(recognizer.scale, recognizer.location(in: view))
        recognizer.scale = 1
    }
}
