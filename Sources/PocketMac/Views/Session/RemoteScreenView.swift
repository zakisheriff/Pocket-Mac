import SwiftUI
import UIKit

/// Shows the Mac's live screen with the pointer drawn locally on top.
/// When `trackpad` is set, the whole view is also a trackpad.
struct RemoteScreenView: UIViewRepresentable {
    let client: RFBClient
    var trackpad: TrackpadGestureHandler.Actions?
    var allowsZoom = false
    var bottomInset: CGFloat = 0

    func makeUIView(context: Context) -> RemoteScreenUIView {
        let view = RemoteScreenUIView()
        if trackpad != nil {
            context.coordinator.handler.macPointsPerTouchPoint = { [weak view] in
                1 / (view?.pointsPerMacPoint ?? 1)
            }
            context.coordinator.handler.attach(to: view)
        }
        configure(view, context: context)
        client.display = view
        return view
    }

    func updateUIView(_ view: RemoteScreenUIView, context: Context) {
        configure(view, context: context)
        if client.display !== view { client.display = view }
    }

    private func configure(_ view: RemoteScreenUIView, context: Context) {
        if var actions = trackpad {
            if allowsZoom {
                actions.pinch = { [weak view] scale in view?.applyPinch(scale) }
            }
            context.coordinator.handler.actions = actions
        }
        view.setBottomInset(bottomInset)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        let handler = TrackpadGestureHandler()
    }
}

/// Renders the Mac's screen straight from the shared IOSurface: each frame
/// is just "contents changed" on a GPU layer, with no image copies.
final class RemoteScreenUIView: UIView, RemoteDisplaySink {
    private let screenLayer = CALayer()
    private let cursorLayer = CALayer()
    private var screenSize: CGSize = .zero
    private var pointer: CGPoint = .zero
    private var cursor: RFBCursor?
    /// Space covered by the keyboard; the Mac screen re-centres above it.
    private var bottomInset: CGFloat = 0

    /// 1 = whole Mac screen fits; above 1 the view zooms in and follows the pointer.
    private(set) var zoom: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        screenLayer.magnificationFilter = .linear
        screenLayer.minificationFilter = .linear
        screenLayer.contentsGravity = .resize
        screenLayer.isOpaque = true
        screenLayer.backgroundColor = UIColor.black.cgColor
        cursorLayer.contentsGravity = .resize
        cursorLayer.contents = Self.arrowImage
        cursorLayer.zPosition = 1
        cursorLayer.isHidden = true
        layer.addSublayer(screenLayer)
        layer.addSublayer(cursorLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: RemoteDisplaySink

    func display(image: CGImage?, size: CGSize) {
        withoutAnimation {
            screenLayer.contents = image
            if size != screenSize {
                screenSize = size
                layoutScreen()
            }
        }
    }

    func pointerMoved(to point: CGPoint) {
        pointer = point
        withoutAnimation {
            if zoom > 1 { layoutScreen() } else { layoutCursor(in: screenLayer.frame, scale: pointsPerMacPoint) }
        }
    }

    func cursorChanged(_ cursor: RFBCursor?) {
        self.cursor = cursor
        withoutAnimation {
            cursorLayer.contents = cursor?.image ?? Self.arrowImage
            layoutScreen()
        }
    }

    // MARK: Layout

    /// Slides the Mac screen up or down to make room for the keyboard,
    /// animated on the GPU so the live view never re-lays out per frame.
    func setBottomInset(_ inset: CGFloat) {
        guard inset != bottomInset else { return }
        bottomInset = inset
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1))
        layoutScreen()
        CATransaction.commit()
    }

    func applyPinch(_ scale: CGFloat) {
        zoom = min(max(zoom * scale, 1), 5)
        withoutAnimation { layoutScreen() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutAnimation { layoutScreen() }
    }

    private var visibleSize: CGSize {
        CGSize(width: bounds.width, height: max(bounds.height - bottomInset, 1))
    }

    /// Mac screen points → view points at the current zoom.
    var pointsPerMacPoint: CGFloat {
        guard screenSize.width > 0, screenSize.height > 0 else { return 1 }
        let visible = visibleSize
        return min(visible.width / screenSize.width, visible.height / screenSize.height) * zoom
    }

    private func layoutScreen() {
        guard screenSize.width > 0, screenSize.height > 0, bounds.width > 0 else {
            screenLayer.frame = .zero
            cursorLayer.isHidden = true
            return
        }
        let visible = visibleSize
        let scale = pointsPerMacPoint
        let size = CGSize(width: screenSize.width * scale, height: screenSize.height * scale)

        func origin(content: CGFloat, available: CGFloat, focus: CGFloat) -> CGFloat {
            guard content > available else { return (available - content) / 2 }
            return min(0, max(available - content, available / 2 - focus * scale))
        }
        let frame = CGRect(
            x: origin(content: size.width, available: visible.width, focus: pointer.x),
            y: origin(content: size.height, available: visible.height, focus: pointer.y),
            width: size.width,
            height: size.height
        )
        screenLayer.frame = frame
        layoutCursor(in: frame, scale: scale)
    }

    private func layoutCursor(in frame: CGRect, scale: CGFloat) {
        guard screenSize.width > 0 else { return }
        cursorLayer.isHidden = false
        let tip = CGPoint(x: frame.minX + pointer.x * scale, y: frame.minY + pointer.y * scale)
        if let cursor {
            // Keep the Mac's own pointer readable even when the screen is shrunk onto a phone.
            let cursorScale = max(scale, 0.75)
            cursorLayer.frame = CGRect(
                x: tip.x - cursor.hotspot.x * cursorScale,
                y: tip.y - cursor.hotspot.y * cursorScale,
                width: CGFloat(cursor.image.width) * cursorScale,
                height: CGFloat(cursor.image.height) * cursorScale
            )
        } else {
            cursorLayer.frame = CGRect(
                x: tip.x - Self.arrowHotspot.x, y: tip.y - Self.arrowHotspot.y,
                width: Self.arrowSize.width, height: Self.arrowSize.height
            )
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: Fallback pointer

    /// macOS Screen Sharing doesn't send its pointer to VNC viewers, so the
    /// phone draws a Mac-style arrow where the pointer is.
    private static let arrowSize = CGSize(width: 15, height: 22)
    private static let arrowHotspot = CGPoint(x: 1.5, y: 1.5)

    private static let arrowImage: CGImage? = {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let renderer = UIGraphicsImageRenderer(size: arrowSize, format: format)
        let image = renderer.image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 1.5, y: 1.5))
            path.addLine(to: CGPoint(x: 1.5, y: 17.5))
            path.addLine(to: CGPoint(x: 5.4, y: 13.8))
            path.addLine(to: CGPoint(x: 8.2, y: 20.2))
            path.addLine(to: CGPoint(x: 10.9, y: 19.0))
            path.addLine(to: CGPoint(x: 8.2, y: 12.8))
            path.addLine(to: CGPoint(x: 13.5, y: 12.8))
            path.close()
            path.lineJoinStyle = .round
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 0.6), blur: 1.2, color: UIColor(white: 0, alpha: 0.45).cgColor)
            UIColor.white.setStroke()
            path.lineWidth = 2.2
            path.stroke()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.black.setFill()
            path.fill()
        }
        return image.cgImage
    }()
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
