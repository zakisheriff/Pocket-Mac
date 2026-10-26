import SwiftUI

/// The live Mac, controlled from the phone.
struct SessionView: View {
    @ObservedObject var client: RFBClient
    @ObservedObject var settings: SettingsStore
    @StateObject private var input: SessionInputController
    @State private var keyboardVisible = false
    @State private var showingSettings = false

    init(client: RFBClient, settings: SettingsStore) {
        self.client = client
        self.settings = settings
        _input = StateObject(wrappedValue: SessionInputController(client: client, settings: settings))
    }

    var body: some View {
        GeometryReader { proxy in
            let portrait = proxy.size.height > proxy.size.width
            if settings.layoutMode == .duo && portrait {
                duoLayout(size: proxy.size)
            } else {
                directLayout(landscape: !portrait)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .overlay { statusOverlay }
        .sheet(isPresented: $showingSettings) { SettingsSheet(settings: settings) }
        .onChange(of: client.state) { _, state in
            if state == .connected { HapticsManager.success() }
        }
    }

    // MARK: Layouts

    /// Regular iPhones: the Mac fills the screen and the screen is the
    /// trackpad. The keyboard slides over the bottom while the Mac screen
    /// glides up above it — the live view itself never resizes.
    private func directLayout(landscape: Bool) -> some View {
        let keyHeight: CGFloat = landscape ? 30 : 42
        let bottomPadding: CGFloat = landscape ? 8 : 26
        let keyboardHeight = MacKeyboardView.height(keyHeight: keyHeight, bottomPadding: bottomPadding)

        return ZStack(alignment: .bottom) {
            RemoteScreenView(
                client: client,
                trackpad: input.trackpadActions,
                allowsZoom: true,
                bottomInset: keyboardVisible ? keyboardHeight : 0,
                pointerSize: CGFloat(settings.pointerSize),
                pointerStyle: settings.pointerStyle
            )
            .overlay(alignment: .topTrailing) {
                controls(showsKeyboardToggle: true)
                    .padding(.top, landscape ? 8 : 4)
                    .padding(.trailing, 12)
            }

            if keyboardVisible {
                MacKeyboardView(input: input, keyHeight: keyHeight, bottomPadding: bottomPadding)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0), value: keyboardVisible)
    }

    /// iPhone Duo: held upright like an open laptop — the Mac on the top
    /// half, a keyboard and trackpad on the bottom half.
    private func duoLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            RemoteScreenView(client: client, pointerSize: CGFloat(settings.pointerSize),
                pointerStyle: settings.pointerStyle)
                .frame(height: size.height * 0.48)
                .overlay(alignment: .topTrailing) {
                    controls(showsKeyboardToggle: false)
                        .padding(.top, 4)
                        .padding(.trailing, 12)
                }

            Rectangle()
                .fill(Color(white: 0.05))
                .frame(height: 6)

            VStack(spacing: 10) {
                MacKeyboardView(input: input, keyHeight: 36)
                TrackpadPad(actions: input.trackpadActions, macScreenWidth: client.screenSize.width)
                    .frame(width: size.width * 0.62)
                    .frame(maxHeight: .infinity)
                    .padding(.bottom, 24)
            }
            .frame(maxHeight: .infinity)
            .background(Color(white: 0.11))
        }
    }

    // MARK: Controls

    private func controls(showsKeyboardToggle: Bool) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                controlButton("gearshape", label: "Settings and help") {
                    HapticsManager.tap()
                    showingSettings = true
                }
                if showsKeyboardToggle {
                    controlButton(keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard",
                                  label: keyboardVisible ? "Hide keyboard" : "Show keyboard") {
                        HapticsManager.tap()
                        keyboardVisible.toggle()
                    }
                }
                controlButton("xmark", label: "Disconnect") {
                    HapticsManager.appOpen()
                    client.disconnect()
                }
            }
        }
    }

    /// Every control the same size, whatever its symbol's natural width.
    private func controlButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    // MARK: Status

    @ViewBuilder
    private var statusOverlay: some View {
        if case .failed(let message) = client.state {
            failureCard(message)
        } else if let message = statusMessage {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("Cancel") {
                    HapticsManager.tap()
                    client.disconnect()
                }
                .buttonStyle(.glass)
            }
            .padding(28)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(32)
        }
    }

    private func failureCard(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            Text("Couldn't Connect")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Close") {
                        HapticsManager.tap()
                        client.acknowledgeFailure()
                    }
                    .buttonStyle(.glass)
                    Button("Try Again") {
                        HapticsManager.appOpen()
                        client.retry()
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: 360)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(24)
    }

    private var statusMessage: String? {
        switch client.state {
        case .connecting: return "Connecting to your Mac…"
        case .authenticating: return "Logging in…"
        case .connected: return client.hasScreen ? nil : "Waiting for the Mac's screen…"
        default: return nil
        }
    }
}
