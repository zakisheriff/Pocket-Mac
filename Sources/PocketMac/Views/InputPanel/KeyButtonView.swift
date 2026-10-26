import SwiftUI

struct KeyButtonView: View {
    let label: String
    var flex: CGFloat = 1
    var compactHeight: Bool = false
    var isToggled: Bool = false
    var height: CGFloat = 38
    /// Delete/arrow keys repeat while held, like a real keyboard.
    var repeatsOnHold: Bool = false
    let action: () -> Void

    @State private var isPressed = false
    @State private var repeatTimer: Timer?

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
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        action()
                        if repeatsOnHold { startRepeating() }
                    }
                    .onEnded { _ in
                        isPressed = false
                        stopRepeating()
                    }
            )
    }

    private func startRepeating() {
        stopRepeating()
        var interval: TimeInterval = 0.42
        func scheduleNext() {
            repeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
                guard isPressed else { return }
                action()
                interval = max(0.06, interval * 0.82)
                scheduleNext()
            }
        }
        scheduleNext()
    }

    private func stopRepeating() {
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}
