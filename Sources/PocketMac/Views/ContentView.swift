import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var client = RFBClient()
    @StateObject private var browser = MacBrowser()
    @StateObject private var savedMacs = SavedMacStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ConnectView(client: client, browser: browser, savedMacs: savedMacs)
            .fullScreenCover(isPresented: sessionIsShowing) {
                SessionView(client: client, settings: settings)
            }
            .onChange(of: client.state) { _, state in
                if case .failed = state { HapticsManager.error() }
            }
            .onAppear { HapticsManager.prepare() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: client.enterBackground()
                case .active: client.enterForeground()
                default: break
                }
            }
    }

    private var sessionIsShowing: Binding<Bool> {
        Binding(
            get: { client.showsSession },
            set: { if !$0 { client.disconnect() } }
        )
    }

}
