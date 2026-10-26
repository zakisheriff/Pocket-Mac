import SwiftUI
import Combine

/// Owns every open window, z-ordering, and which app is currently frontmost
/// (so the menu bar and dock can react to it).
@MainActor
final class WindowManager: ObservableObject {

    @Published private(set) var windows: [DesktopWindow] = []
    @Published private(set) var order: [UUID] = []
    @Published var launchpadVisible = false
    @Published var spotlightVisible = false

    /// Bounds of the usable desktop canvas, updated by DesktopView on layout.
    var canvasBounds: CGRect = .zero

    /// Dock icon hit rects, in desktop-canvas coordinates, reported live by
    /// DockView so indirect (trackpad) clicks can reach the dock.
    @Published var dockIconFrames: [AppKind: CGRect] = [:]
    @Published var launchpadButtonFrame: CGRect = .zero

    private var bounceTokens: [AppKind: UUID] = [:]
    @Published private(set) var bouncingApps: Set<AppKind> = []

    var frontmostWindow: DesktopWindow? {
        guard let topID = order.last else { return nil }
        return windows.first { $0.id == topID }
    }

    var runningApps: Set<AppKind> {
        Set(windows.map(\.kind))
    }

    func isFrontmost(_ id: UUID) -> Bool {
        order.last == id
    }

    func zIndex(of id: UUID) -> Double {
        Double(order.firstIndex(of: id) ?? 0)
    }

    // MARK: - Opening / closing

    func open(_ kind: AppKind) {
        if kind == .trash {
            // Trash has no window content of its own in this simulation;
            // treat it as a quick glance rather than a persistent window.
        }

        if let existing = windows.first(where: { $0.kind == kind && !$0.isMinimized }) {
            bringToFront(existing.id)
            return
        }
        if let minimized = windows.first(where: { $0.kind == kind && $0.isMinimized }) {
            restore(minimized.id)
            return
        }

        bounce(kind)
        HapticsManager.appOpen()

        let size = clampedSize(kind.defaultSize)
        let origin = spawnOrigin(for: size)
        var window = DesktopWindow(kind: kind, position: origin, size: size)
        window.isMinimized = false
        windows.append(window)
        order.append(window.id)
    }

    func close(_ id: UUID) {
        windows.removeAll { $0.id == id }
        order.removeAll { $0 == id }
        HapticsManager.tap()
    }

    func minimize(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].isMinimized = true
        HapticsManager.tap()
    }

    func restore(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        windows[index].isMinimized = false
        bringToFront(id)
    }

    func toggleFullscreen(_ id: UUID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        if windows[index].isFullscreen {
            if let prev = windows[index].preFullscreenFrame {
                windows[index].position = prev.position
                windows[index].size = prev.size
            }
            windows[index].isFullscreen = false
        } else {
            windows[index].preFullscreenFrame = (windows[index].position, windows[index].size)
            windows[index].position = CGPoint(x: canvasBounds.minX + 8, y: canvasBounds.minY + 8)
            windows[index].size = CGSize(width: max(canvasBounds.width - 16, 100),
                                          height: max(canvasBounds.height - 16, 80))
            windows[index].isFullscreen = true
        }
        HapticsManager.tap()
        bringToFront(id)
    }

    func bringToFront(_ id: UUID) {
        guard windows.contains(where: { $0.id == id }) else { return }
        order.removeAll { $0 == id }
        order.append(id)
    }

    // MARK: - Dragging

    func move(_ id: UUID, to newPosition: CGPoint) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        guard !windows[index].isFullscreen else { return }
        windows[index].position = clampedPosition(newPosition, size: windows[index].size)
    }

    func resize(_ id: UUID, to newSize: CGSize) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else { return }
        guard !windows[index].isFullscreen else { return }
        let maxWidth = max(canvasBounds.width - 8, 160)
        let maxHeight = max(canvasBounds.height - 8, 120)
        windows[index].size = CGSize(width: min(newSize.width, maxWidth), height: min(newSize.height, maxHeight))
    }

    private func clampedPosition(_ point: CGPoint, size: CGSize) -> CGPoint {
        guard canvasBounds != .zero else { return point }
        let minX = canvasBounds.minX - size.width + 60
        let maxX = canvasBounds.maxX - 60
        let minY = canvasBounds.minY
        let maxY = canvasBounds.maxY - 24
        return CGPoint(x: min(max(point.x, minX), maxX), y: min(max(point.y, minY), maxY))
    }

    /// Shrinks a desktop-scale window size to fit the actual (phone-sized)
    /// canvas, preserving aspect ratio so Safari/Finder/etc. still look
    /// like real windows instead of clipped desktop-sized panes.
    private func clampedSize(_ size: CGSize) -> CGSize {
        guard canvasBounds != .zero else { return size }
        let maxWidth = max(canvasBounds.width - 28, 160)
        let maxHeight = max(canvasBounds.height - 56, 120)
        guard size.width > maxWidth || size.height > maxHeight else { return size }
        let scale = min(maxWidth / size.width, maxHeight / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func spawnOrigin(for size: CGSize) -> CGPoint {
        let openCount = CGFloat(windows.count % 6)
        let base = CGPoint(
            x: canvasBounds.midX - size.width / 2 + openCount * 16,
            y: canvasBounds.minY + 24 + openCount * 16
        )
        return base
    }

    // MARK: - Dock bounce animation

    private func bounce(_ kind: AppKind) {
        bouncingApps.insert(kind)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            self?.bouncingApps.remove(kind)
        }
    }

    // MARK: - Reset

    func closeAll() {
        windows.removeAll()
        order.removeAll()
    }
}
