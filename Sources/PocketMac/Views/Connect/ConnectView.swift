import SwiftUI

/// Who the login sheet is for.
enum LoginTarget: Identifiable {
    case discovered(MacBrowser.DiscoveredMac)
    case saved(SavedMac)
    case manual

    var id: String {
        switch self {
        case .discovered(let mac): return "discovered-\(mac.name)"
        case .saved(let mac): return "saved-\(mac.id)"
        case .manual: return "manual"
        }
    }
}

struct ConnectView: View {
    @ObservedObject var client: RFBClient
    @ObservedObject var browser: MacBrowser
    @ObservedObject var savedMacs: SavedMacStore
    @ObservedObject var settings: SettingsStore

    @State private var loginTarget: LoginTarget?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                if !savedMacs.macs.isEmpty {
                    Section("My Macs") {
                        ForEach(savedMacs.macs) { mac in
                            Button {
                                HapticsManager.tap()
                                connect(to: mac)
                            } label: {
                                MacRow(name: mac.name, subtitle: mac.subtitle, isOnline: isOnline(mac))
                            }
                            .swipeActions {
                                Button("Forget", systemImage: "trash", role: .destructive) {
                                    HapticsManager.appOpen()
                                    savedMacs.remove(mac)
                                }
                                Button("Edit", systemImage: "pencil") {
                                    HapticsManager.tap()
                                    loginTarget = .saved(mac)
                                }
                            }
                        }
                    }
                }

                if !unsavedNearbyMacs.isEmpty || browser.macs.isEmpty || browser.isLocalNetworkDenied {
                    Section {
                        ForEach(unsavedNearbyMacs) { mac in
                            Button {
                                HapticsManager.tap()
                                loginTarget = .discovered(mac)
                            } label: {
                                MacRow(name: mac.name, subtitle: "On this network", isOnline: true)
                            }
                        }
                        if browser.macs.isEmpty && !browser.isLocalNetworkDenied {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Looking for Macs with Screen Sharing on…")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("On this network")
                    } footer: {
                        if browser.isLocalNetworkDenied {
                            Text("Pocket Mac can't see your network. Turn on Settings › Privacy & Security › Local Network › Pocket Mac.")
                        }
                    }
                }

                Section {
                    Button {
                        HapticsManager.tap()
                        loginTarget = .manual
                    } label: {
                        Label("Connect by Address", systemImage: "network")
                    }
                }

                Section("Set up your Mac") {
                    SetupStep(number: 1, text: "On your Mac, open System Settings › General › Sharing.")
                    SetupStep(number: 2, text: "Turn on Screen Sharing.")
                    SetupStep(number: 3, text: "Click ⓘ next to it and allow your user account.")
                    SetupStep(number: 4, text: "Keep the Mac on the same Wi‑Fi as this iPhone, then pick it above and log in with your Mac username and password.")
                }
            }
            .navigationTitle("Pocket Mac")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticsManager.tap()
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(item: $loginTarget) { target in
                LoginSheet(target: target, savedMacs: savedMacs) { request in
                    client.connect(request)
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(settings: settings)
            }
        }
        .onAppear { browser.start() }
    }

    private var unsavedNearbyMacs: [MacBrowser.DiscoveredMac] {
        browser.macs.filter { found in
            !savedMacs.macs.contains { $0.address == .bonjour(serviceName: found.name) }
        }
    }

    private func isOnline(_ mac: SavedMac) -> Bool? {
        guard case .bonjour(let name) = mac.address else { return nil }
        return browser.macs.contains { $0.name == name }
    }

    private func connect(to mac: SavedMac) {
        guard let password = savedMacs.password(for: mac) else {
            loginTarget = .saved(mac)
            return
        }
        savedMacs.save(name: mac.name, address: mac.address, username: mac.username, password: password)
        client.connect(MacConnectionRequest(
            endpoint: mac.endpoint, displayName: mac.name, username: mac.username, password: password
        ))
    }
}

private struct MacRow: View {
    let name: String
    let subtitle: String
    /// nil when unknown (Macs added by address).
    let isOnline: Bool?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "laptopcomputer")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
            }
            Spacer()
            if let isOnline {
                Circle()
                    .fill(isOnline ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel(isOnline ? "Available" : "Not found on this network")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct SetupStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.tint)
            Text(text)
                .font(.subheadline)
        }
    }
}
