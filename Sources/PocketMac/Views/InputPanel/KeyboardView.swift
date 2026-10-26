import SwiftUI

/// A compact, functional Mac-style QWERTY keyboard.
struct KeyboardView: View {
    @ObservedObject var keyboard: KeyboardInputManager
    var compact: Bool = false

    private let row1 = Array("1234567890")
    private let row2 = Array("qwertyuiop")
    private let row3 = Array("asdfghjkl")
    private let row4 = Array("zxcvbnm")

    var body: some View {
        VStack(spacing: compact ? 4 : 6) {
            rowView(row1.map(String.init))
            rowView(row2.map(String.init))
            HStack(spacing: compact ? 4 : 6) {
                keyButton("tab", label: "tab", flex: 1.4)
                rowView(row3.map(String.init), embedded: true)
                keyButton("return", label: "return", flex: 1.6, action: { keyboard.pressReturn() })
            }
            HStack(spacing: compact ? 4 : 6) {
                keyButton("shift", label: "shift", flex: 1.8, isToggled: keyboard.isShiftOn, action: { keyboard.toggleShift() })
                rowView(row4.map(String.init), embedded: true)
                keyButton("delete", label: "⌫", flex: 1.4, action: { keyboard.pressBackspace() })
            }
            HStack(spacing: compact ? 4 : 6) {
                keyButton("fn", label: "fn", flex: 0.8)
                keyButton("control", label: "control", flex: 1.1)
                keyButton("option", label: "option", flex: 1.1)
                keyButton("command", label: "cmd", flex: 1.2)
                keyButton("space", label: "", flex: 4, action: { keyboard.press(" ") })
                keyButton("command2", label: "cmd", flex: 1.2)
                keyButton("option2", label: "option", flex: 1.1)
                keyButton("left", label: "◀", flex: 0.7)
                VStack(spacing: 2) {
                    keyButton("up", label: "▲", flex: 1, compactHeight: true)
                    keyButton("down", label: "▼", flex: 1, compactHeight: true)
                }
                keyButton("right", label: "▶", flex: 0.7)
            }
        }
        .padding(compact ? 6 : 10)
        .background(Color(white: 0.16))
    }

    @ViewBuilder
    private func rowView(_ keys: [String], embedded: Bool = false) -> some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(keys, id: \.self) { key in
                keyButton(key, label: key)
            }
        }
    }

    private func keyButton(
        _ id: String,
        label: String,
        flex: CGFloat = 1,
        isToggled: Bool = false,
        compactHeight: Bool = false,
        action: (() -> Void)? = nil
    ) -> some View {
        KeyButtonView(
            label: label,
            flex: flex,
            compactHeight: compactHeight,
            isToggled: isToggled,
            height: compact ? 30 : 38,
            repeatsOnHold: id == "delete"
        ) {
            if let action {
                action()
            } else {
                keyboard.press(label)
            }
        }
    }
}
