import SwiftUI

/// A real trackpad surface: relative-motion drag moves the cursor, a quick
/// tap clicks whatever is under the cursor, and pressing on a window's title
/// bar then dragging moves that window — all driven indirectly, like a real
/// Mac trackpad.
struct TrackpadView: View {
    @ObservedObject var cursor: CursorManager
    @ObservedObject var windowManager: WindowManager
    var compact: Bool = false

    @State private var lastTranslation: CGSize = .zero
    @State private var draggingWindowID: UUID?

    var body: some View {
        RoundedRectangle(cornerRadius: compact ? 18 : 14, style: .continuous)
            .fill(Color(white: 0.82))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 18 : 14, style: .continuous)
                    .strokeBorder(.black.opacity(0.15), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(.black.opacity(0.18))
                    .frame(width: 44, height: 4)
                    .padding(.bottom, 6)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture)
            .onTapGesture {
                click()
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let delta = CGSize(
                    width: value.translation.width - lastTranslation.width,
                    height: value.translation.height - lastTranslation.height
                )
                lastTranslation = value.translation

                if draggingWindowID == nil, value.translation == .zero,
                   case .titleBar(let id) = windowManager.hitTest(cursor.position) {
                    draggingWindowID = id
                    windowManager.bringToFront(id)
                }

                cursor.applyDelta(delta)

                if let id = draggingWindowID, let window = windowManager.windows.first(where: { $0.id == id }) {
                    windowManager.move(id, to: CGPoint(x: window.position.x + delta.width * cursor.sensitivity,
                                                        y: window.position.y + delta.height * cursor.sensitivity))
                }
            }
            .onEnded { _ in
                lastTranslation = .zero
                draggingWindowID = nil
                cursor.isPressed = false
            }
    }

    private func click() {
        HapticsManager.click()
        cursor.isPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            cursor.isPressed = false
        }
        windowManager.handlePrimaryClick(at: cursor.position)
    }
}
