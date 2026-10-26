import SwiftUI

/// The pointer arrow rendered over the desktop, driven by CursorManager.
struct CursorView: View {
    let isPressed: Bool

    var body: some View {
        ArrowShape()
            .fill(.white)
            .overlay(ArrowShape().stroke(.black.opacity(0.7), lineWidth: 1))
            .frame(width: 16, height: 22)
            .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            .scaleEffect(isPressed ? 0.85 : 1.0, anchor: .topLeading)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
            .allowsHitTesting(false)
    }
}

private struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: rect.height * 0.82))
        path.addLine(to: CGPoint(x: rect.width * 0.32, y: rect.height * 0.62))
        path.addLine(to: CGPoint(x: rect.width * 0.52, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.68, y: rect.height * 0.92))
        path.addLine(to: CGPoint(x: rect.width * 0.48, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.46))
        path.closeSubpath()
        return path
    }
}

#Preview {
    CursorView(isPressed: false)
        .padding()
        .background(Color.blue)
}
