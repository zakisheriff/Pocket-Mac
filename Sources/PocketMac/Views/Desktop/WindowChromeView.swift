import SwiftUI

/// A draggable, closable macOS-style window frame hosting one app's content.
struct WindowChromeView: View {
    let window: DesktopWindow
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var keyboard: KeyboardInputManager
    let isFrontmost: Bool

    @State private var dragStart: CGPoint?
    @State private var resizeStart: CGSize?

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().overlay(Color.black.opacity(0.3))
            AppContentView(kind: window.kind, keyboard: keyboard)
                .frame(width: window.size.width, height: max(window.size.height - 28, 10))
                .clipped()
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .environment(\.colorScheme, .light)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.black.opacity(0.25), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(isFrontmost ? 0.4 : 0.22), radius: isFrontmost ? 18 : 8, y: 8)
        .frame(width: window.size.width, height: window.size.height, alignment: .top)
        .position(x: window.position.x + window.size.width / 2, y: window.position.y + window.size.height / 2)
        .opacity(window.isMinimized ? 0 : 1)
        .scaleEffect(window.isMinimized ? 0.1 : 1, anchor: .bottom)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: window.isMinimized)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: window.isFullscreen)
        .overlay(alignment: .bottomTrailing) {
            if !window.isFullscreen {
                resizeHandle
            }
        }
        .onTapGesture { windowManager.bringToFront(window.id) }
    }

    private var titleBar: some View {
        ZStack {
            HStack(spacing: 8) {
                trafficLight(.red) { windowManager.close(window.id) }
                trafficLight(.yellow) { windowManager.minimize(window.id) }
                trafficLight(.green) { windowManager.toggleFullscreen(window.id) }
                Spacer()
            }
            .padding(.horizontal, 10)

            Text(window.kind.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black.opacity(0.65))
                .lineLimit(1)
        }
        .frame(height: 28)
        .frame(width: window.size.width)
        .background(Color.white.opacity(0.4))
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                windowManager.bringToFront(window.id)
                let start = dragStart ?? window.position
                if dragStart == nil { dragStart = window.position }
                windowManager.move(window.id, to: CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black.opacity(0.35))
            .padding(6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = resizeStart ?? window.size
                        if resizeStart == nil { resizeStart = window.size }
                        let newSize = CGSize(
                            width: max(200, start.width + value.translation.width),
                            height: max(140, start.height + value.translation.height)
                        )
                        windowManager.resize(window.id, to: newSize)
                    }
                    .onEnded { _ in resizeStart = nil }
            )
    }

    private enum LightColor { case red, yellow, green }

    private func trafficLight(_ color: LightColor, action: @escaping () -> Void) -> some View {
        let fill: Color
        switch color {
        case .red: fill = Color(red: 1.0, green: 0.37, blue: 0.33)
        case .yellow: fill = Color(red: 1.0, green: 0.74, blue: 0.18)
        case .green: fill = Color(red: 0.16, green: 0.78, blue: 0.25)
        }
        return Circle()
            .fill(fill)
            .frame(width: 12, height: 12)
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            .contentShape(Circle())
            .onTapGesture {
                HapticsManager.tap()
                action()
            }
    }
}
