import SwiftUI

/// The simulated macOS desktop: wallpaper, menu bar, windows and dock.
/// Used both as the "screen half" in Duo mode and full-screen in Direct mode.
struct DesktopView: View {
    @ObservedObject var windowManager: WindowManager
    @ObservedObject var keyboard: KeyboardInputManager
    @EnvironmentObject private var settings: SettingsStore

    var showsDock: Bool = true
    var cursorOverlay: AnyView?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                settings.wallpaper.gradient
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MenuBarView(
                        frontmostApp: windowManager.frontmostWindow?.kind,
                        onAppleMenu: { windowManager.open(.aboutThisMac) },
                        onSpotlight: { windowManager.spotlightVisible.toggle() }
                    )
                    Spacer(minLength: 0)
                }

                ForEach(windowManager.windows) { window in
                    WindowChromeView(
                        window: window,
                        windowManager: windowManager,
                        keyboard: keyboard,
                        isFrontmost: windowManager.isFrontmost(window.id)
                    )
                    .zIndex(windowManager.zIndex(of: window.id))
                }

                if showsDock {
                    VStack {
                        Spacer()
                        DockView(windowManager: windowManager) {
                            windowManager.launchpadVisible.toggle()
                        }
                        .padding(.bottom, 6)
                    }
                }

                if let cursorOverlay {
                    cursorOverlay
                }

                if windowManager.launchpadVisible {
                    LaunchpadView(windowManager: windowManager)
                        .transition(.opacity.combined(with: .scale(scale: 1.05)))
                }

                if windowManager.spotlightVisible {
                    SpotlightView(windowManager: windowManager, keyboard: keyboard)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: windowManager.launchpadVisible)
            .animation(.easeOut(duration: 0.2), value: windowManager.spotlightVisible)
            .onAppear { windowManager.canvasBounds = proxy.frame(in: .local) }
            .onChange(of: proxy.size) { _, _ in windowManager.canvasBounds = proxy.frame(in: .local) }
            .clipped()
        }
    }
}
