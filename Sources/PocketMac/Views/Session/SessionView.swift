import SwiftUI
import UIKit

/// The live Mac, controlled from the phone.
struct SessionView: View {
    @ObservedObject var client: RFBClient
    @ObservedObject var settings: SettingsStore
    @StateObject private var input: SessionInputController
    @State private var keyboardVisible = false
    @State private var showingTextEntry = false

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
        .sheet(isPresented: $showingTextEntry) {
            SendTextSheet { text in client.type(text) }
        }
        .onChange(of: client.state) { _, state in
            if state == .connected { HapticsManager.success() }
        }
    }

    // MARK: Layouts

    /// Regular iPhones: the Mac fills the screen and the screen is the trackpad.
    private func directLayout(landscape: Bool) -> some View {
        VStack(spacing: 0) {
            RemoteScreenView(client: client, trackpad: input.trackpadActions, allowsZoom: true)
                .overlay(alignment: .topTrailing) {
                    controls
                        .padding(.top, landscape ? 8 : 4)
                        .padding(.trailing, 12)
                }
            if keyboardVisible {
                MacKeyboardView(input: input, keyHeight: landscape ? 30 : 40)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.snappy, value: keyboardVisible)
    }

    /// iPhone Duo: held upright like an open laptop — the Mac on the top
    /// half, a keyboard and trackpad on the bottom half.
    private func duoLayout(size: CGSize) -> some View {
        VStack(spacing: 0) {
            RemoteScreenView(client: client)
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

    private var controls: some View {
        controls(showsKeyboardToggle: true)
    }

    private func controls(showsKeyboardToggle: Bool) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if showsKeyboardToggle {
                    Button {
                        HapticsManager.tap()
                        keyboardVisible.toggle()
                    } label: {
                        Image(systemName: keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(keyboardVisible ? "Hide keyboard" : "Show keyboard")
                }

                Menu {
                    Button("Type with iPhone Keyboard", systemImage: "character.cursor.ibeam") {
                        HapticsManager.tap()
                        showingTextEntry = true
                    }
                    Button("Paste iPhone Clipboard on Mac", systemImage: "doc.on.clipboard") {
                        HapticsManager.tap()
                        pasteIPhoneClipboard()
                    }
                    Divider()
                    Button("Spotlight", systemImage: "magnifyingglass") {
                        input.tapKeysym(0x20, modifiers: [.command])
                    }
                    Button("Mission Control", systemImage: "rectangle.3.group") {
                        input.tapKeysym(Keysym.up, modifiers: [.control])
                    }
                    Button("Switch App", systemImage: "square.on.square") {
                        input.tapKeysym(Keysym.tab, modifiers: [.command])
                    }
                    Button("Quit App", systemImage: "xmark.app") {
                        input.tapKeysym(0x71, modifiers: [.command])
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .simultaneousGesture(TapGesture().onEnded { HapticsManager.tap() })
                .accessibilityLabel("More")

                Button {
                    HapticsManager.appOpen()
                    client.disconnect()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Disconnect")
            }
        }
    }

    private func pasteIPhoneClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        client.sendClipboard(text)
        // Give the Mac a moment to take the clipboard before pasting it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            client.tapKey(0x76, modifiers: [.command])
        }
    }

    // MARK: Status

    @ViewBuilder
    private var statusOverlay: some View {
        if let message = statusMessage {
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

    private var statusMessage: String? {
        switch client.state {
        case .connecting: return "Connecting to your Mac…"
        case .authenticating: return "Logging in…"
        case .connected: return client.screen == nil ? "Waiting for the Mac's screen…" : nil
        default: return nil
        }
    }
}

/// Type longer text with the iPhone's own keyboard (autocorrect, dictation)
/// and send it to the Mac in one go.
private struct SendTextSheet: View {
    let send: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextField("Text to type on your Mac", text: $text, axis: .vertical)
                .lineLimit(4...12)
                .focused($focused)
                .padding()
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding()
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle("Type on Mac")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            HapticsManager.tap()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            HapticsManager.appOpen()
                            send(text)
                            dismiss()
                        }
                        .disabled(text.isEmpty)
                    }
                }
                .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }
}
