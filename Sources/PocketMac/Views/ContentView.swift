import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore()
    @StateObject private var client = RFBClient()
    @StateObject private var browser = MacBrowser()
    @StateObject private var savedMacs = SavedMacStore()

    var body: some View {
        ConnectView(client: client, browser: browser, savedMacs: savedMacs, settings: settings)
            .fullScreenCover(isPresented: sessionIsShowing) {
                SessionView(client: client, settings: settings)
            }
            .alert("Couldn't Connect", isPresented: failureIsShowing) {
                Button("OK", role: .cancel) { HapticsManager.tap() }
            } message: {
                Text(failureMessage)
            }
            .onChange(of: client.state) { _, state in
                if case .failed = state { HapticsManager.error() }
            }
            .onAppear { HapticsManager.prepare() }
    }

    private var sessionIsShowing: Binding<Bool> {
        Binding(
            get: { client.isActive },
            set: { if !$0 { client.disconnect() } }
        )
    }

    private var failureIsShowing: Binding<Bool> {
        Binding(
            get: { if case .failed = client.state { return true } else { return false } },
            set: { if !$0 { client.acknowledgeFailure() } }
        )
    }

    private var failureMessage: String {
        if case .failed(let message) = client.state { return message }
        return ""
    }
}
