import SwiftUI

struct KeyButtonView: View {
    let label: String
    var flex: CGFloat = 1
    var compactHeight: Bool = false
    var isToggled: Bool = false
    var height: CGFloat = 38
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity)
            .frame(height: compactHeight ? height / 2 - 1 : height)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isToggled ? Color.accentColor.opacity(0.7) : (isPressed ? Color(white: 0.4) : Color(white: 0.26)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.black.opacity(0.35), lineWidth: 0.5)
            )
            .layoutPriority(flex)
            .frame(maxWidth: .infinity)
            .scaleEffect(isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in
                        isPressed = false
                        action()
                    }
            )
    }
}
