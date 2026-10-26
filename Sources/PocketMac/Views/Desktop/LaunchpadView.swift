import SwiftUI

struct LaunchpadView: View {
    @ObservedObject var windowManager: WindowManager
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 22)]

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
                .onTapGesture { windowManager.launchpadVisible = false }

            VStack(spacing: 18) {
                Text("Launchpad")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 20)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(AppKind.allCases.filter { $0 != .trash }) { app in
                            VStack(spacing: 6) {
                                Image(systemName: app.symbolName)
                                    .font(.system(size: 30, weight: .semibold))
                                    .frame(width: 60, height: 60)
                                    .background(RoundedRectangle(cornerRadius: 16).fill(app.tint.gradient))
                                    .foregroundStyle(.white)
                                Text(app.displayName)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                HapticsManager.appOpen()
                                windowManager.open(app)
                                windowManager.launchpadVisible = false
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
    }
}
