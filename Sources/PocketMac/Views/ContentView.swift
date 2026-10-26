import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var windowManager = WindowManager()
    @StateObject private var keyboard = KeyboardInputManager()

    @State private var orientation = UIDevice.current.orientation
    private let orientationPublisher = NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)

    var body: some View {
        Group {
            switch settings.layoutMode {
            case .direct:
                DirectModeView(windowManager: windowManager, keyboard: keyboard)
            case .duo:
                if isLandscape {
                    LaptopModeView(windowManager: windowManager, keyboard: keyboard)
                } else {
                    ClosedLidView()
                }
            }
        }
        .environmentObject(settings)
        .onAppear { HapticsManager.prepare() }
        .onReceive(orientationPublisher) { _ in
            let current = UIDevice.current.orientation
            if current.isValidInterfaceOrientation {
                orientation = current
            }
        }
    }

    private var isLandscape: Bool {
        orientation.isLandscape || orientation == .unknown
    }
}

#Preview {
    ContentView()
}
