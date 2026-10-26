import SwiftUI

struct DockView: View {
    @ObservedObject var windowManager: WindowManager
    var onLaunchpad: () -> Void = {}
    var compact: Bool = false

    @State private var pressedApp: AppKind?

    private var iconSize: CGFloat { compact ? 30 : 38 }
    private var spacing: CGFloat { compact ? 8 : 10 }

    var body: some View {
        HStack(spacing: spacing) {
            Button(action: onLaunchpad) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: iconSize * 0.5))
                    .frame(width: iconSize, height: iconSize)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: iconSize * 0.3))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Launchpad")
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: LaunchpadButtonFramePreferenceKey.self,
                        value: proxy.frame(in: .named(DesktopCoordinateSpace.name))
                    )
                }
            )

            Rectangle()
                .fill(.white.opacity(0.25))
                .frame(width: 1, height: iconSize * 0.7)

            ForEach(AppKind.dockApps) { app in
                dockIcon(app)
            }
        }
        .padding(.horizontal, spacing + 2)
        .padding(.vertical, spacing * 0.6)
        .background(
            RoundedRectangle(cornerRadius: (iconSize + spacing) * 0.42, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: (iconSize + spacing) * 0.42, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func dockIcon(_ app: AppKind) -> some View {
        let isRunning = windowManager.runningApps.contains(app)
        let isBouncing = windowManager.bouncingApps.contains(app)

        VStack(spacing: 4) {
            Image(systemName: app.symbolName)
                .font(.system(size: iconSize * 0.46, weight: .semibold))
                .frame(width: iconSize, height: iconSize)
                .background(
                    RoundedRectangle(cornerRadius: iconSize * 0.3)
                        .fill(app.tint.gradient)
                )
                .foregroundStyle(.white)
                .scaleEffect(pressedApp == app ? 1.28 : (isBouncing ? 1.18 : 1.0))
                .offset(y: isBouncing ? -10 : 0)
                .shadow(color: .black.opacity(0.35), radius: pressedApp == app ? 6 : 2, y: 2)
                .animation(.spring(response: 0.28, dampingFraction: 0.45), value: pressedApp)
                .animation(.interpolatingSpring(stiffness: 260, damping: 9), value: isBouncing)

            Circle()
                .fill(.white.opacity(isRunning ? 0.9 : 0))
                .frame(width: 4, height: 4)
        }
        .contentShape(Rectangle())
        .accessibilityLabel(app.displayName)
        .accessibilityAddTraits(isRunning ? [.isButton, .isSelected] : .isButton)
        .onTapGesture {
            windowManager.open(app)
        }
        .onLongPressGesture(minimumDuration: 0.01, maximumDistance: 40) {
        } onPressingChanged: { pressing in
            pressedApp = pressing ? app : (pressedApp == app ? nil : pressedApp)
            if pressing { HapticsManager.selectionChanged() }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: DockIconFramePreferenceKey.self,
                    value: [app: proxy.frame(in: .named(DesktopCoordinateSpace.name))]
                )
            }
        )
    }
}

#Preview {
    DockView(windowManager: WindowManager())
        .padding()
        .background(Color.indigo)
}
