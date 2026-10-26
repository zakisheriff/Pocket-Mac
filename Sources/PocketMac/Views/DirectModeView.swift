import SwiftUI

/// Regular, non-folding iPhone mode (17, 17 Pro, 17 Pro Max, …): the full
/// screen is the desktop and you drive it with direct touch — tap a dock
/// icon, drag a title bar, tap a text field. A keyboard sheet rises when
/// text input is needed, and an optional floating trackpad can be toggled
/// on for indirect, Mac-like pointer control.
struct DirectModeView: View {
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var keyboard: KeyboardInputManager
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var floatingCursor = CursorManager()
    @State private var floatingPadCenter = CGPoint(x: 90, y: 160)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                DesktopView(
                    windowManager: windowManager,
                    keyboard: keyboard,
                    cursorOverlay: settings.trackpadOverlayEnabled
                        ? AnyView(CursorView(isPressed: floatingCursor.isPressed).position(floatingCursor.position))
                        : nil
                )
                .onAppear { floatingCursor.setBounds(CGRect(origin: .zero, size: proxy.size)) }
                .onChange(of: proxy.size) { _, newSize in
                    floatingCursor.setBounds(CGRect(origin: .zero, size: newSize))
                }
                .onChange(of: settings.pointerSensitivity, initial: true) { _, value in
                    floatingCursor.sensitivity = CGFloat(value)
                }

                if settings.trackpadOverlayEnabled {
                    FloatingTrackpad(cursor: floatingCursor, windowManager: windowManager, center: $floatingPadCenter)
                        .position(floatingPadCenter)
                }

                if keyboard.target != .none {
                    keyboardSheet
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: keyboard.target)
            .ignoresSafeArea()
        }
    }

    @State private var sheetDragOffset: CGFloat = 0

    private var keyboardSheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 6)

            HStack {
                Spacer()
                Button {
                    dismissKeyboard()
                } label: {
                    Text("Done")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            KeyboardView(keyboard: keyboard, compact: true)
        }
        .background(Color(white: 0.09))
        .offset(y: sheetDragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    sheetDragOffset = max(0, value.translation.height)
                }
                .onEnded { value in
                    if value.translation.height > 60 {
                        dismissKeyboard()
                    }
                    sheetDragOffset = 0
                }
        )
    }

    private func dismissKeyboard() {
        keyboard.target = .none
        HapticsManager.tap()
    }
}

/// A small, draggable floating trackpad — the "AssistiveTouch" equivalent
/// for driving the desktop cursor on a non-folding iPhone.
private struct FloatingTrackpad: View {
    @ObservedObject var cursor: CursorManager
    @ObservedObject var windowManager: WindowManager
    @Binding var center: CGPoint

    @State private var dragStart: CGPoint?

    var body: some View {
        TrackpadView(cursor: cursor, windowManager: windowManager, compact: true)
            .frame(width: 150, height: 96)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black.opacity(0.4))
                    .padding(6)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let start = dragStart ?? center
                                if dragStart == nil { dragStart = center }
                                center = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
    }
}
