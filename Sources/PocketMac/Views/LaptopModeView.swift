import SwiftUI

/// "iPhone Duo" simulation: landscape, split into a desktop screen half and
/// a trackpad + keyboard deck half — like a laptop folded open on your palm.
struct LaptopModeView: View {
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var keyboard: KeyboardInputManager
    @StateObject private var cursor = CursorManager()

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                DesktopView(
                    windowManager: windowManager,
                    keyboard: keyboard,
                    cursorOverlay: AnyView(
                        CursorView(isPressed: cursor.isPressed)
                            .position(cursor.position)
                    )
                )
                .frame(height: proxy.size.height * 0.56)
                .clipShape(RoundedCorner(radius: 14, corners: [.topLeft, .topRight]))

                Rectangle()
                    .fill(Color.black)
                    .frame(height: 6)

                TrackpadKeyboardView(cursor: cursor, windowManager: windowManager, keyboard: keyboard)
                    .frame(height: proxy.size.height * 0.44 - 6)
                    .clipShape(RoundedCorner(radius: 14, corners: [.bottomLeft, .bottomRight]))
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.black, lineWidth: 10)
            )
            .padding(6)
            .background(Color.black)
            .onAppear {
                cursor.setBounds(CGRect(origin: .zero, size: CGSize(width: proxy.size.width, height: proxy.size.height * 0.56)))
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

/// Rounds only the specified corners — used to fake the two halves of a
/// folded laptop lid meeting at a hinge.
struct RoundedCorner: Shape {
    var radius: CGFloat = 12
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
