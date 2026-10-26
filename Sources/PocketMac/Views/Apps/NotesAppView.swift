import SwiftUI
import Combine

struct NotesAppView: View {
    @ObservedObject var keyboard: KeyboardInputManager
    @State private var text: String = "Hello"
    @State private var cursorBlink = true
    private let blinkTimer = Timer.publish(every: 0.55, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("New Note")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(Date.now, style: .date)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color(white: 0.96))

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    Text(text.isEmpty ? " " : text)
                        .font(.system(size: 15))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if isFocused {
                        Rectangle()
                            .fill(.black.opacity(cursorBlink ? 0.8 : 0))
                            .frame(width: 1.5, height: 17)
                    }
                }
                .padding(12)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                keyboard.target = .notes
                HapticsManager.tap()
            }
        }
        .background(Color.white)
        .onReceive(keyboard.keyPressed) { action in
            guard keyboard.target == .notes else { return }
            apply(action)
        }
        .onReceive(blinkTimer) { _ in cursorBlink.toggle() }
        .onAppear { keyboard.target = .notes }
    }

    private var isFocused: Bool { keyboard.target == .notes }

    private func apply(_ action: KeyboardInputManager.KeyAction) {
        switch action {
        case .character(let c): text.append(c)
        case .backspace: if !text.isEmpty { text.removeLast() }
        case .return: text.append("\n")
        case .tab: text.append("\t")
        case .escape: break
        }
    }
}
