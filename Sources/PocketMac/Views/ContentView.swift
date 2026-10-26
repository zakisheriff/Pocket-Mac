import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var client = RFBClient()
    @StateObject private var browser = MacBrowser()
    @StateObject private var savedMacs = SavedMacStore()

    var body: some View {
        ConnectView(client: client, browser: browser, savedMacs: savedMacs)
            .fullScreenCover(isPresented: sessionIsShowing) {
                SessionView(client: client, settings: settings)
            }
            .onChange(of: client.state) { _, state in
                if case .failed = state { HapticsManager.error() }
            }
            .onAppear { HapticsManager.prepare() }
    }

    private var sessionIsShowing: Binding<Bool> {
        Binding(
            get: { client.showsSession },
            set: { if !$0 { client.disconnect() } }
        )
    }

}
