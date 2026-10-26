import UIKit

/// Turns touches on any UIView into Mac input.
///
/// Trackpad: one finger moves the pointer, tap clicks, two-finger tap
/// right-clicks, two-finger drag scrolls, press-and-hold then drag holds the
/// button down, pinch zooms.
///
/// Touch (when `macPoint` is set): no pointer to steer — a tap clicks right
/// where the finger is, a one-finger swipe scrolls what's under it, and
/// press-and-hold then drag drags it, like a touchscreen.
@MainActor
final class TrackpadGestureHandler: NSObject, UIGestureRecognizerDelegate {
    struct Actions {
        var move: (CGVector, _ speed: CGFloat) -> Void = { _, _ in }
        var click: () -> Void = {}
        var rightClick: () -> Void = {}
        var scroll: (CGVector) -> Void = { _ in }
        var dragBegan: () -> Void = {}
        var dragEnded: () -> Void = {}
        /// Puts the pointer on a Mac screen point (touch mode).
        var point: (CGPoint) -> Void = { _ in }
        /// A one-finger swipe in touch mode: always scrolls the Mac.
        var swipe: (CGVector) -> Void = { _ in }
        /// Scale change and the pinch centre in the view.
        var pinch: ((CGFloat, CGPoint) -> Void)?
    }

    var actions = Actions()
    /// Mac screen points per touch point, so a swipe across the surface
    /// covers the same share of the Mac screen whatever the zoom or size.
    var macPointsPerTouchPoint: () -> CGFloat = { 1 }
    /// Set for touch mode: the Mac screen point under a touch, if any.
    var macPoint: ((CGPoint) -> CGPoint?)?
    private var isTouchMode: Bool { macPoint != nil }
    private var recognizers: [UIGestureRecognizer] = []

    /// Off while the view isn't taking input (e.g. the Duo screen in
    /// trackpad mode, where the deck below is the trackpad).
    var isEnabled = true {
        didSet { recognizers.forEach { $0.isEnabled = isEnabled } }
    }

    /// Moves the pointer onto the touch, in touch mode.
    private func pointAt(_ recognizer: UIGestureRecognizer) {
        guard let macPoint, let view = recognizer.view,
              let point = macPoint(recognizer.location(in: view)) else { return }
        actions.point(point)
    }
    private var lastDragLocation: CGPoint?

    private func scaled(_ x: CGFloat, _ y: CGFloat) -> CGVector {
        let factor = macPointsPerTouchPoint()
        return CGVector(dx: x * factor, dy: y * factor)
    }

    func attach(to view: UIView) {
        view.isMultipleTouchEnabled = true

        let rightTap = UITapGestureRecognizer(target: self, action: #selector(handleRightTap(_:)))
        rightTap.numberOfTouchesRequired = 2

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
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

        recognizers = [rightTap, tap, hold, pan, scroll, pinch]
        for recognizer in recognizers {
            recognizer.isEnabled = isEnabled
            view.addGestureRecognizer(recognizer)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (gestureRecognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer) ||
        (gestureRecognizer is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        HapticsManager.click()
        pointAt(recognizer)
        actions.click()
    }

    @objc private func handleRightTap(_ recognizer: UITapGestureRecognizer) {
        HapticsManager.appOpen()
        pointAt(recognizer)
        actions.rightClick()
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard let view = recognizer.view else { return }
        if isTouchMode {
            // Scroll whatever is under the finger, content following it.
            if recognizer.state == .began { pointAt(recognizer) }
            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)
            actions.swipe(CGVector(dx: translation.x, dy: translation.y))
            return
        }
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
            pointAt(recognizer)
            actions.dragBegan()
        case .changed:
            if isTouchMode {
                pointAt(recognizer)
            } else if let last = lastDragLocation {
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
