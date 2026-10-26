import SwiftUI

/// Runtime state for one open window on the simulated desktop.
struct DesktopWindow: Identifiable, Equatable {
    let id: UUID
    let kind: AppKind
    var position: CGPoint
    var size: CGSize
    var isMinimized: Bool = false
    var isFullscreen: Bool = false
    var preFullscreenFrame: (position: CGPoint, size: CGSize)?

    static func == (lhs: DesktopWindow, rhs: DesktopWindow) -> Bool {
        lhs.id == rhs.id &&
        lhs.position == rhs.position &&
        lhs.size == rhs.size &&
        lhs.isMinimized == rhs.isMinimized &&
        lhs.isFullscreen == rhs.isFullscreen
    }

    init(kind: AppKind, position: CGPoint, size: CGSize? = nil) {
        self.id = UUID()
        self.kind = kind
        self.position = position
        self.size = size ?? kind.defaultSize
    }

    var frame: CGRect {
        CGRect(x: position.x, y: position.y, width: size.width, height: size.height)
    }

    var titleBarFrame: CGRect {
        CGRect(x: position.x, y: position.y, width: size.width, height: 28)
    }
}
