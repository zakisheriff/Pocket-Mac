import SwiftUI

/// A full Mac keyboard. Each row is laid out from the keys' relative widths,
/// so letter keys stay full size next to wide keys like return and shift.
struct MacKeyboardView: View {
    @ObservedObject var input: SessionInputController
    var keyHeight: CGFloat = 38
    var bottomPadding: CGFloat = 0

    static let spacing: CGFloat = 5
    static let topPadding: CGFloat = 8

    /// Total height, known up front so the Mac screen can make room for the
    /// keyboard in the same animation that slides it in.
    static func height(keyHeight: CGFloat, bottomPadding: CGFloat) -> CGFloat {
        let rows = CGFloat(MacKey.rows.count)
        return topPadding + rows * keyHeight + (rows - 1) * spacing + 8 + bottomPadding
    }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.width - 12
            VStack(spacing: Self.spacing) {
                ForEach(Array(MacKey.rows.enumerated()), id: \.offset) { _, row in
                    let units = row.reduce(0) { $0 + $1.width }
                    let unit = (available - Self.spacing * CGFloat(row.count - 1)) / units
                    HStack(spacing: Self.spacing) {
                        ForEach(row) { key in
                            Group {
                                if key.action == .verticalArrows {
                                    VStack(spacing: 2) {
                                        KeyCap(label: "↑", isOn: false, isWide: false, compact: true) {
                                            input.tapKeysym(Keysym.up)
                                        }
                                        KeyCap(label: "↓", isOn: false, isWide: false, compact: true) {
                                            input.tapKeysym(Keysym.down)
                                        }
                                    }
                                } else {
                                    KeyCap(label: input.label(for: key), isOn: isOn(key), isWide: key.width > 1) {
                                        input.press(key)
                                    }
                                }
                            }
                            .frame(width: unit * key.width, height: keyHeight)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, Self.topPadding)
        }
        .frame(height: Self.height(keyHeight: keyHeight, bottomPadding: bottomPadding))
        .background(Color(white: 0.11))
    }

    private func isOn(_ key: MacKey) -> Bool {
        switch key.action {
        case .modifier(let modifier): return input.isActive(modifier)
        case .capsLock: return input.capsLock
        default: return false
        }
    }
}

private struct KeyCap: View {
    let label: String
    let isOn: Bool
    let isWide: Bool
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: compact ? 11 : (isWide ? 13 : 17), weight: isWide ? .medium : .regular))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.white : Color(white: 0.24))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyPressStyle())
        .accessibilityLabel(label.isEmpty ? "space" : label)
    }
}

/// Brightens the key while pressed, like a real key travel.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.15 : 0)
    }
}
