import SwiftUI

/// A full Mac keyboard. Each row is laid out from the keys' relative widths,
/// so letter keys stay full size next to wide keys like return and shift.
struct MacKeyboardView: View {
    @ObservedObject var input: SessionInputController
    var keyHeight: CGFloat = 38
    var spacing: CGFloat = 5

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(MacKey.rows.enumerated()), id: \.offset) { _, row in
                GeometryReader { proxy in
                    let units = row.reduce(0) { $0 + $1.width }
                    let unit = (proxy.size.width - spacing * CGFloat(row.count - 1)) / units
                    HStack(spacing: spacing) {
                        ForEach(row) { key in
                            KeyCap(
                                label: input.label(for: key),
                                isOn: isOn(key),
                                isWide: key.width > 1
                            ) {
                                input.press(key)
                            }
                            .frame(width: unit * key.width)
                        }
                    }
                }
                .frame(height: keyHeight)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: isWide ? 13 : 17, weight: isWide ? .medium : .regular))
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

/// Darkens the key while pressed, like a real key travel.
private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.15 : 0)
    }
}
