import OSLog
import SwiftUI
import UIKit

/// Shows the Mac's live screen with a pointer ring drawn locally on top.
/// When `trackpad` is set, the whole view is also a trackpad.
struct RemoteScreenView: UIViewRepresentable {
    let client: RFBClient
    var trackpad: TrackpadGestureHandler.Actions?
    var allowsZoom = false
    var bottomInset: CGFloat = 0
    var pointerSize: CGFloat = 24
    var pointerStyle: PointerStyle = .macArrow
    /// Touch mode: no pointer, touches land right where the finger is.
    var touchMode = false

    func makeUIView(context: Context) -> RemoteScreenUIView {
        let view = RemoteScreenUIView()
        context.coordinator.handler.macPointsPerTouchPoint = { [weak view] in
            1 / (view?.pointsPerMacPoint ?? 1)
        }
        context.coordinator.handler.attach(to: view)
        configure(view, context: context)
        client.addDisplay(view)
        return view
    }

    func updateUIView(_ view: RemoteScreenUIView, context: Context) {
        configure(view, context: context)
    }

    static func dismantleUIView(_ view: RemoteScreenUIView, coordinator: Coordinator) {
        view.client?.removeDisplay(view)
    }

    private func configure(_ view: RemoteScreenUIView, context: Context) {
        view.client = client
        let handler = context.coordinator.handler
        handler.isEnabled = trackpad != nil
        handler.macPoint = touchMode ? { [weak view] location in view?.macPoint(at: location) } : nil
        view.showsPointer = !touchMode
        if var actions = trackpad {
            if allowsZoom {
                actions.pinch = { [weak view] scale, center in view?.zoom(by: scale, around: center) }
                // Zoomed in, two fingers move around the zoomed screen;
                // at normal size they scroll the Mac.
                let scrollMac = actions.scroll
                actions.scroll = { [weak view] delta in
                    guard let view else { return }
                    if view.isZoomed { view.pan(by: delta) } else { scrollMac(delta) }
                }
            }
            handler.actions = actions
        }
        view.setPointer(style: pointerStyle, size: pointerSize)
        view.setBottomInset(bottomInset)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        let handler = TrackpadGestureHandler()
    }
}

/// Renders the Mac's screen through Metal straight from the shared
/// framebuffer (falling back to zero-copy images), and keeps a viewport
/// (zoom + pan) that the pointer never yanks around.
final class RemoteScreenUIView: UIView, RemoteDisplaySink {
    weak var client: RFBClient?

    private let screenLayer = CALayer()
    private let metal = MetalScreenRenderer()
    private var usesMetal = false
    private var surface: IOSurface?
    private let pointerLayer = CALayer()
    private var screenSize: CGSize = .zero
    private var pointer: CGPoint = .zero
    private var cursor: RFBCursor?
    private var pointerSize: CGFloat = 24
    private var pointerStyle: PointerStyle = .macArrow
    /// Space covered by the keyboard; the Mac screen re-centres above it.
    private var bottomInset: CGFloat = 0

    /// 1 = whole Mac screen fits.
    private(set) var zoom: CGFloat = 1
    /// Top-left of the zoomed screen in view points (only used when zoomed).
    private var panOrigin: CGPoint = .zero

    var isZoomed: Bool { zoom > 1.01 }

    /// Hidden in touch mode, where the finger is the pointer.
    var showsPointer = true {
        didSet {
            guard showsPointer != oldValue else { return }
            withoutAnimation { layoutScreen() }
        }
    }

    /// The Mac screen point under a point in this view, or nil off-screen.
    func macPoint(at location: CGPoint) -> CGPoint? {
        let frame = currentScreenFrame()
        guard frame.width > 0, frame.contains(location) else { return nil }
        let scale = pointsPerMacPoint
        return CGPoint(x: (location.x - frame.minX) / scale, y: (location.y - frame.minY) / scale)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        screenLayer.magnificationFilter = .linear
        screenLayer.minificationFilter = .linear
        screenLayer.contentsGravity = .resize
        screenLayer.isOpaque = true
        screenLayer.backgroundColor = UIColor.black.cgColor
        pointerLayer.zPosition = 1
        pointerLayer.isHidden = true
        pointerLayer.contentsGravity = .resize
        applyPointerImage()
        layer.addSublayer(screenLayer)
        if let metal { layer.addSublayer(metal.layer) }
        layer.addSublayer(pointerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: RemoteDisplaySink

    func display(surface: IOSurface?, size: CGSize) {
        self.surface = surface
        usesMetal = metal?.setSurface(surface, width: Int(size.width), height: Int(size.height)) ?? false
        if surface != nil {
            Logger(subsystem: "com.zakisheriff.pocketmac", category: "session")
                .notice("Pocket Mac: rendering \(Int(size.width))x\(Int(size.height)) with \(self.usesMetal ? "Metal (zero-copy)" : "image fallback", privacy: .public)")
        }
        withoutAnimation {
            metal?.layer.isHidden = !usesMetal
            screenLayer.isHidden = usesMetal
            if !usesMetal { screenLayer.contents = nil }
            if size != screenSize {
                screenSize = size
            }
            layoutScreen()
        }
    }

    func frameUpdated() {
        if usesMetal {
            metal?.draw()
        } else if let surface {
            withoutAnimation {
                screenLayer.contents = RFBFramebuffer.liveImage(
                    of: surface, width: Int(screenSize.width), height: Int(screenSize.height)
                )
            }
        }
    }

    func pointerMoved(to point: CGPoint) {
        pointer = point
        withoutAnimation {
            if isZoomed && showsPointer { keepPointerVisible() }
            layoutScreen()
        }
    }

    func cursorChanged(_ cursor: RFBCursor?) {
        self.cursor = cursor
        withoutAnimation {
            if let cursor {
                pointerLayer.contents = cursor.image
            } else {
                applyPointerImage()
            }
            layoutScreen()
        }
    }

    // MARK: Viewport

    func zoom(by scale: CGFloat, around center: CGPoint) {
        let old = currentScreenFrame()
        let newZoom = min(max(zoom * scale, 1), 6)
        guard newZoom != zoom, old.width > 0 else { return }
        // Keep the Mac point under the fingers in place while zooming.
        let anchor = CGPoint(x: (center.x - old.minX) / old.width, y: (center.y - old.minY) / old.height)
        zoom = newZoom < 1.02 ? 1 : newZoom
        let size = scaledSize
        panOrigin = CGPoint(x: center.x - anchor.x * size.width, y: center.y - anchor.y * size.height)
        withoutAnimation { layoutScreen() }
    }

    func pan(by delta: CGVector) {
        panOrigin.x += delta.dx
        panOrigin.y += delta.dy
        withoutAnimation { layoutScreen() }
    }

    /// Nudges the zoomed view only when the pointer reaches its edge,
    /// so moving the pointer never drags the whole screen around.
    private func keepPointerVisible() {
        let frame = currentScreenFrame()
        let scale = pointsPerMacPoint
        let tip = CGPoint(x: frame.minX + pointer.x * scale, y: frame.minY + pointer.y * scale)
        let margin: CGFloat = 36
        let visible = CGRect(origin: .zero, size: visibleSize).insetBy(dx: margin, dy: margin)
        if tip.x < visible.minX { panOrigin.x += visible.minX - tip.x }
        if tip.x > visible.maxX { panOrigin.x -= tip.x - visible.maxX }
        if tip.y < visible.minY { panOrigin.y += visible.minY - tip.y }
        if tip.y > visible.maxY { panOrigin.y -= tip.y - visible.maxY }
    }

    // MARK: Layout

    func setPointer(style: PointerStyle, size: CGFloat) {
        guard style != pointerStyle || size != pointerSize else { return }
        pointerStyle = style
        pointerSize = size
        withoutAnimation {
            applyPointerImage()
            layoutScreen()
        }
    }

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

    override func layoutSubviews() {
        super.layoutSubviews()
        withoutAnimation { layoutScreen() }
    }

    private var visibleSize: CGSize {
        CGSize(width: bounds.width, height: max(bounds.height - bottomInset, 1))
    }

    private var fitScale: CGFloat {
        guard screenSize.width > 0, screenSize.height > 0 else { return 1 }
        let visible = visibleSize
        return min(visible.width / screenSize.width, visible.height / screenSize.height)
    }

    /// Mac screen points → view points at the current zoom.
    var pointsPerMacPoint: CGFloat { fitScale * zoom }

    private var scaledSize: CGSize {
        CGSize(width: screenSize.width * pointsPerMacPoint, height: screenSize.height * pointsPerMacPoint)
    }

    private func currentScreenFrame() -> CGRect {
        let visible = visibleSize
        let size = scaledSize
        func axis(content: CGFloat, available: CGFloat, requested: CGFloat) -> CGFloat {
            guard content > available else { return (available - content) / 2 }
            return min(0, max(available - content, requested))
        }
        return CGRect(
            x: axis(content: size.width, available: visible.width, requested: panOrigin.x),
            y: axis(content: size.height, available: visible.height, requested: panOrigin.y),
            width: size.width,
            height: size.height
        )
    }

    private func layoutScreen() {
        guard screenSize.width > 0, screenSize.height > 0, bounds.width > 0 else {
            screenLayer.frame = .zero
            pointerLayer.isHidden = true
            return
        }
        let frame = currentScreenFrame()
        panOrigin = frame.origin
        screenLayer.frame = frame
        metal?.layer.frame = frame

        let scale = pointsPerMacPoint
        let tip = CGPoint(x: frame.minX + pointer.x * scale, y: frame.minY + pointer.y * scale)
        pointerLayer.isHidden = !showsPointer
        if let cursor {
            let cursorScale = max(scale, 0.75)
            pointerLayer.frame = CGRect(
                x: tip.x - cursor.hotspot.x * cursorScale,
                y: tip.y - cursor.hotspot.y * cursorScale,
                width: CGFloat(cursor.image.width) * cursorScale,
                height: CGFloat(cursor.image.height) * cursorScale
            )
        } else {
            // macOS draws its own arrow into the screen; the ring marks where
            // the pointer is right now, so the two read as one pointer.
            let size = PointerImages.size(for: pointerStyle, pointerSize: pointerSize)
            let hotspot = PointerImages.hotspot(for: pointerStyle)
            pointerLayer.frame = CGRect(
                x: tip.x - hotspot.x * size.width, y: tip.y - hotspot.y * size.height,
                width: size.width, height: size.height
            )
        }
    }

    private func applyPointerImage() {
        guard cursor == nil else { return }
        pointerLayer.contents = PointerImages.image(for: pointerStyle, pointerSize: pointerSize).cgImage
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
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
