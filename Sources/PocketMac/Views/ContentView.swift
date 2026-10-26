import SwiftUI

struct ContentView: View {
    @StateObject private var settings = SettingsStore()

    var body: some View {
        Text("Pocket Mac")
            .environmentObject(settings)
    }
}
