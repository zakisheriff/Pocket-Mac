import SwiftUI

@main
struct PocketMacApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

/// Locks orientation support flags at the application level so the desktop
/// simulation can freely read `UIDevice.current.orientation` without the
/// system fighting us over rotation.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        return true
    }
}
