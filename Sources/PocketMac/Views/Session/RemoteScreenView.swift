import SwiftUI
import UIKit

/// Shows the Mac's live screen with the pointer drawn locally on top.
/// When `trackpad` is set, the whole view is also a trackpad.
struct RemoteScreenView: UIViewRepresentable {
    @ObservedObject var client: RFBClient
    var trackpad: TrackpadGestureHandler.Actions?
    var allowsZoom = false

    func makeUIView(context: Context) -> RemoteScreenUIView {
        let view = RemoteScreenUIView()
        if var actions = trackpad {
            if allowsZoom {
                actions.pinch = { [weak view] scale in view?.applyPinch(scale) }
            }
            context.coordinator.handler.actions = actions
            context.coordinator.handler.macPointsPerTouchPoint = { [weak view] in
                1 / (view?.pointsPerMacPoint ?? 1)
            }
            context.coordinator.handler.attach(to: view)
        }
        return view
    }

    func updateUIView(_ view: RemoteScreenUIView, context: Context) {
        if var actions = trackpad {
            if allowsZoom {
                actions.pinch = { [weak view] scale in view?.applyPinch(scale) }
            }
            context.coordinator.handler.actions = actions
        }
        view.render(image: client.screen, screenSize: client.screenSize, pointer: client.pointer, cursor: client.cursor)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        let handler = TrackpadGestureHandler()
    }
}

final class RemoteScreenUIView: UIView {
    private let screenLayer = CALayer()
    private let cursorLayer = CALayer()
    private var screenSize: CGSize = .zero
    private var pointer: CGPoint = .zero
    private var cursor: RFBCursor?

    /// 1 = whole Mac screen fits; above 1 the view zooms in and follows the pointer.
    private(set) var zoom: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        screenLayer.magnificationFilter = .linear
        screenLayer.minificationFilter = .trilinear
        screenLayer.contentsGravity = .resize
        cursorLayer.contentsGravity = .resize
        cursorLayer.zPosition = 1
        layer.addSublayer(screenLayer)
        layer.addSublayer(cursorLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func render(image: CGImage?, screenSize: CGSize, pointer: CGPoint, cursor: RFBCursor?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let image, (screenLayer.contents as! CGImage?) !== image {
            screenLayer.contents = image
        }
        if cursor != self.cursor {
            cursorLayer.contents = cursor?.image
        }
        self.screenSize = screenSize
        self.pointer = pointer
        self.cursor = cursor
        layoutScreen()
        CATransaction.commit()
    }

    func applyPinch(_ scale: CGFloat) {
        zoom = min(max(zoom * scale, 1), 5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutScreen()
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutScreen()
    }

    /// Mac screen points → view points at the current zoom.
    var pointsPerMacPoint: CGFloat {
        guard screenSize.width > 0, screenSize.height > 0 else { return 1 }
        return min(bounds.width / screenSize.width, bounds.height / screenSize.height) * zoom
    }

    private func layoutScreen() {
        guard screenSize.width > 0, screenSize.height > 0, bounds.width > 0 else {
            screenLayer.frame = .zero
            cursorLayer.isHidden = true
            return
        }
        let scale = pointsPerMacPoint
        let size = CGSize(width: screenSize.width * scale, height: screenSize.height * scale)

        func origin(content: CGFloat, available: CGFloat, focus: CGFloat) -> CGFloat {
            guard content > available else { return (available - content) / 2 }
            return min(0, max(available - content, available / 2 - focus * scale))
        }
        let frame = CGRect(
            x: origin(content: size.width, available: bounds.width, focus: pointer.x),
            y: origin(content: size.height, available: bounds.height, focus: pointer.y),
            width: size.width,
            height: size.height
        )
        screenLayer.frame = frame

        guard let cursor else {
            cursorLayer.isHidden = true
            return
        }
        // Keep the pointer readable even when a big Mac screen is shrunk onto a phone.
        let cursorScale = max(scale, 0.75)
        cursorLayer.isHidden = false
        cursorLayer.frame = CGRect(
            x: frame.minX + pointer.x * scale - cursor.hotspot.x * cursorScale,
            y: frame.minY + pointer.y * scale - cursor.hotspot.y * cursorScale,
            width: CGFloat(cursor.image.width) * cursorScale,
            height: CGFloat(cursor.image.height) * cursorScale
        )
    }
}

/// The Duo deck's physical-looking trackpad.
struct TrackpadPad: UIViewRepresentable {
    var actions: TrackpadGestureHandler.Actions
    /// Width of the Mac screen, so crossing the pad crosses the screen.
    var macScreenWidth: CGFloat

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor(white: 0.8, alpha: 1)
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor(white: 0, alpha: 0.15).cgColor
        context.coordinator.handler.actions = actions
        context.coordinator.handler.attach(to: view)
        update(view, context: context)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.handler.actions = actions
        update(view, context: context)
    }

    private func update(_ view: UIView, context: Context) {
        let width = macScreenWidth
        context.coordinator.handler.macPointsPerTouchPoint = { [weak view] in
            guard let padWidth = view?.bounds.width, padWidth > 0, width > 0 else { return 1 }
            return width / padWidth
        }
    }

    func makeCoordinator() -> RemoteScreenView.Coordinator { RemoteScreenView.Coordinator() }
}
