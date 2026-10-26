import SwiftUI

/// What a point on the desktop canvas resolves to, for indirect (trackpad)
/// interaction — mirrors what a real cursor click would hit.
enum DesktopHitResult {
    case closeButton(UUID)
    case minimizeButton(UUID)
    case zoomButton(UUID)
    case titleBar(UUID)
    case windowBody(UUID)
    case dockIcon(AppKind)
    case launchpadButton
    case empty
}

extension WindowManager {

    /// Resolves a point (in desktop-canvas coordinates) to whatever is
    /// underneath it, topmost window first, then the dock.
    func hitTest(_ point: CGPoint) -> DesktopHitResult {
        for id in order.reversed() {
            guard let window = windows.first(where: { $0.id == id }), !window.isMinimized else { continue }
            guard window.frame.contains(point) else { continue }

            if window.titleBarFrame.contains(point) {
                let relativeX = point.x - window.position.x
                if (10...22).contains(relativeX) { return .closeButton(id) }
                if (30...42).contains(relativeX) { return .minimizeButton(id) }
                if (50...62).contains(relativeX) { return .zoomButton(id) }
                return .titleBar(id)
            }
            return .windowBody(id)
        }

        for (app, frame) in dockIconFrames where frame.contains(point) {
            return .dockIcon(app)
        }

        if launchpadButtonFrame.contains(point) {
            return .launchpadButton
        }

        return .empty
    }

    func handlePrimaryClick(at point: CGPoint) {
        switch hitTest(point) {
        case .closeButton(let id): close(id)
        case .minimizeButton(let id): minimize(id)
        case .zoomButton(let id): toggleFullscreen(id)
        case .titleBar(let id), .windowBody(let id): bringToFront(id)
        case .dockIcon(let app): open(app)
        case .launchpadButton: launchpadVisible.toggle()
        case .empty: break
        }
    }
}
