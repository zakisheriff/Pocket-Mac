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
    @State private var showingSetupGuide = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)
                        header
                        Spacer().frame(height: 40)
                        macs
                        Spacer(minLength: 40)
                        actions
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .background { BackdropGradient().ignoresSafeArea() }
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
            .sheet(isPresented: $showingSetupGuide) {
                SetupGuideSheet()
            }
        }
        .onAppear { browser.start() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 64, weight: .ultraLight))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
            VStack(spacing: 6) {
                Text("Pocket Mac")
                    .font(.system(size: 34, weight: .bold))
                Text("Your Mac, in your hand.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private var macs: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                ForEach(savedMacs.macs) { mac in
                    MacCard(name: mac.name, status: status(for: mac)) {
                        connect(to: mac)
                    }
                    .contextMenu {
                        Button("Edit Login", systemImage: "person.badge.key") {
                            HapticsManager.tap()
                            loginTarget = .saved(mac)
                        }
                        Button("Forget This Mac", systemImage: "trash", role: .destructive) {
                            HapticsManager.appOpen()
                            savedMacs.remove(mac)
                        }
                    }
                }

                ForEach(unsavedNearbyMacs) { mac in
                    MacCard(name: mac.name, status: .available) {
                        loginTarget = .discovered(mac)
                    }
                }

                if browser.macs.isEmpty && savedMacs.macs.isEmpty {
                    SearchingCard(isDenied: browser.isLocalNetworkDenied)
                }
            }
        }
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    HapticsManager.tap()
                    loginTarget = .manual
                } label: {
                    Text("Connect by Address")
                        .font(.subheadline.weight(.medium))
                }
                Button {
                    HapticsManager.tap()
                    showingSetupGuide = true
                } label: {
                    Image(systemName: "questionmark")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonBorderShape(.circle)
                .accessibilityLabel("How to set up your Mac")
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
    }

    // MARK: Data

    private var unsavedNearbyMacs: [MacBrowser.DiscoveredMac] {
        browser.macs.filter { found in
            !savedMacs.macs.contains { $0.address == .bonjour(serviceName: found.name) }
        }
    }

    private func status(for mac: SavedMac) -> MacCard.Status {
        guard case .bonjour(let name) = mac.address else { return .address(mac.subtitle) }
        return browser.macs.contains { $0.name == name } ? .available : .notNearby
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

// MARK: - Cards

private struct MacCard: View {
    enum Status {
        case available
        case notNearby
        case address(String)

        var text: String {
            switch self {
            case .available: return "Available"
            case .notNearby: return "Not nearby"
            case .address(let place): return place
            }
        }

        var color: Color {
            switch self {
            case .available: return .green
            case .notNearby: return .secondary
            case .address: return .blue
            }
        }
    }

    let name: String
    let status: Status
    let action: () -> Void

    var body: some View {
        Button {
            HapticsManager.appOpen()
            action()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "macbook")
                    .font(.system(size: 30, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.displayName(name))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 7, height: 7)
                        Text(status.text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .contentShape(.rect(cornerRadius: 28))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        .accessibilityLabel("\(Self.displayName(name)), \(status.text)")
    }

    /// macOS adds " (2)" to a Bonjour name when it clashes; hide that noise.
    static func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: #" \(\d+\)$"#, with: "", options: .regularExpression)
    }
}

private struct SearchingCard: View {
    let isDenied: Bool

    var body: some View {
        HStack(spacing: 14) {
            if isDenied {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(.orange)
            } else {
                ProgressView()
            }
            Text(isDenied
                 ? "Allow Local Network for Pocket Mac in Settings › Privacy & Security."
                 : "Looking for Macs nearby…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

// MARK: - Setup

private struct SetupSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set up your Mac")
                .font(.headline)
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(step)
                        .font(.subheadline)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    static let steps = [
        "On your Mac, open System Settings › General › Sharing.",
        "Turn on Screen Sharing.",
        "Click ⓘ and allow your user account.",
        "Keep both on the same Wi‑Fi, then log in with your Mac username and password.",
    ]
}

private struct SetupGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 52, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                SetupSteps()
                Spacer()
            }
            .padding(24)
            .navigationTitle("Set Up Your Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticsManager.tap()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Backdrop

/// A soft, wallpaper-like gradient for the glass to sit on.
private struct BackdropGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.6, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: colorScheme == .dark ? darkColors : lightColors
        )
    }

    private var lightColors: [Color] {
        [
            Color(red: 0.93, green: 0.95, blue: 1.00), Color(red: 0.88, green: 0.92, blue: 1.00), Color(red: 0.95, green: 0.91, blue: 0.99),
            Color(red: 0.90, green: 0.95, blue: 0.99), Color(red: 0.97, green: 0.97, blue: 0.99), Color(red: 0.92, green: 0.90, blue: 0.99),
            Color(red: 0.96, green: 0.96, blue: 0.98), Color(red: 0.93, green: 0.94, blue: 0.99), Color(red: 0.97, green: 0.95, blue: 0.97),
        ]
    }

    private var darkColors: [Color] {
        [
            Color(red: 0.05, green: 0.07, blue: 0.16), Color(red: 0.07, green: 0.10, blue: 0.24), Color(red: 0.13, green: 0.07, blue: 0.22),
            Color(red: 0.04, green: 0.09, blue: 0.18), Color(red: 0.06, green: 0.06, blue: 0.10), Color(red: 0.10, green: 0.06, blue: 0.18),
            Color(red: 0.03, green: 0.04, blue: 0.08), Color(red: 0.05, green: 0.06, blue: 0.12), Color(red: 0.07, green: 0.05, blue: 0.10),
        ]
    }
}
