import SwiftUI
import Combine

struct SpotlightView: View {
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var keyboard: KeyboardInputManager
    @State private var query = ""

    private var results: [AppKind] {
        guard !query.isEmpty else { return [] }
        return AppKind.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.6))
                    Text(query.isEmpty ? "Spotlight Search" : query)
                        .foregroundStyle(query.isEmpty ? .white.opacity(0.4) : .white)
                        .font(.system(size: 20, weight: .light))
                    Spacer()
                }
                .padding(16)

                if !results.isEmpty {
                    Divider().overlay(.white.opacity(0.2))
                    ForEach(results) { app in
                        HStack {
                            Image(systemName: app.symbolName)
                                .foregroundStyle(app.tint)
                                .frame(width: 24)
                            Text(app.displayName)
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            windowManager.open(app)
                            dismiss()
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .environment(\.colorScheme, .dark)
            .frame(maxWidth: 420)
            .padding(.top, 70)
            .shadow(color: .black.opacity(0.4), radius: 30, y: 20)
        }
        .onReceive(keyboard.keyPressed) { action in
            switch action {
            case .character(let c): query.append(c)
            case .backspace: if !query.isEmpty { query.removeLast() }
            case .return: if let first = results.first { windowManager.open(first); dismiss() }
            case .escape: dismiss()
            case .tab: break
            }
        }
        .onAppear { keyboard.target = .spotlight }
    }

    private func dismiss() {
        windowManager.spotlightVisible = false
        keyboard.target = .none
        query = ""
    }
}
