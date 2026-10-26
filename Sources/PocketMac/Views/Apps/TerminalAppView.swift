import SwiftUI
import Combine

struct TerminalAppView: View {
    @ObservedObject var keyboard: KeyboardInputManager
    @State private var lines: [String] = [
        "Last login: today on ttys000",
        "zaki@pocket-mac ~ % neofetch",
        "        .:'            zaki@pocket-mac",
        "    __ :'__            -----------------",
        " .'`__`-'__``.         OS: Pocket Mac 1.0",
        ":__________.-'         Host: iPhone",
        ":__________:           Kernel: Simulated",
        " '.__.-.__.'           Shell: pocketsh",
        "        '--'",
        "zaki@pocket-mac ~ % _",
    ]
    @State private var currentInput = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                    HStack(spacing: 0) {
                        Text("zaki@pocket-mac ~ % ")
                            .foregroundStyle(.green)
                        Text(currentInput)
                            .foregroundStyle(.green)
                        Rectangle()
                            .fill(.green)
                            .frame(width: 7, height: 13)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .id("cursor")
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: currentInput) { _, _ in
                proxy.scrollTo("cursor", anchor: .bottom)
            }
        }
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture {
            keyboard.target = .terminal
            HapticsManager.tap()
        }
        .onReceive(keyboard.keyPressed) { action in
            guard keyboard.target == .terminal else { return }
            apply(action)
        }
        .onAppear { keyboard.target = .terminal }
    }

    private func apply(_ action: KeyboardInputManager.KeyAction) {
        switch action {
        case .character(let c): currentInput.append(c)
        case .backspace: if !currentInput.isEmpty { currentInput.removeLast() }
        case .return:
            let command = currentInput
            currentInput = ""
            if command.trimmingCharacters(in: .whitespaces) == "clear" {
                lines.removeAll()
                return
            }
            lines.append("zaki@pocket-mac ~ % " + command)
            let reply = response(for: command)
            if !reply.isEmpty { lines.append(reply) }
        case .tab: currentInput.append("    ")
        case .escape: break
        }
    }

    private func response(for command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "": return ""
        case "ls": return "Applications  Desktop  Documents  Downloads"
        case "pwd": return "/Users/zaki"
        case "whoami": return "zaki"
        case "date": return Date.now.formatted()
        default: return "zsh: command not found: \(trimmed)"
        }
    }
}
