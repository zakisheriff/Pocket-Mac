import SwiftUI
import WebKit
import Combine

struct SafariAppView: View {
    @ObservedObject var keyboard: KeyboardInputManager
    @State private var addressText = "https://www.apple.com"
    @State private var pendingLoadURL: URL? = URL(string: "https://www.apple.com")
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var navigationToken = UUID()
    @State private var backToken = UUID()
    @State private var forwardToken = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(canGoBack ? .black : .black.opacity(0.25))
                    .contentShape(Rectangle())
                    .onTapGesture { if canGoBack { HapticsManager.tap(); backToken = UUID() } }
                Image(systemName: "chevron.right")
                    .foregroundStyle(canGoForward ? .black : .black.opacity(0.25))
                    .contentShape(Rectangle())
                    .onTapGesture { if canGoForward { HapticsManager.tap(); forwardToken = UUID() } }

                HStack(spacing: 6) {
                    Image(systemName: isLoading ? "circle.dotted" : "lock.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(addressText)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color(white: 0.93)))
                .contentShape(Capsule())
                .onTapGesture {
                    keyboard.target = .safariAddressBar
                    HapticsManager.tap()
                }

                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.black.opacity(0.7))
                    .onTapGesture { reload() }
            }
            .font(.system(size: 13, weight: .medium))
            .padding(8)
            .background(Color(white: 0.97))

            Divider()

            WebContainerView(
                url: pendingLoadURL,
                navigationToken: navigationToken,
                backToken: backToken,
                forwardToken: forwardToken,
                isLoading: $isLoading,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                resolvedAddress: $addressText
            )
        }
        .background(Color.white)
        .onReceive(keyboard.keyPressed) { action in
            guard keyboard.target == .safariAddressBar else { return }
            apply(action)
        }
    }

    private func apply(_ action: KeyboardInputManager.KeyAction) {
        switch action {
        case .character(let c): addressText.append(c)
        case .backspace: if !addressText.isEmpty { addressText.removeLast() }
        case .return: navigate()
        case .tab: break
        case .escape: keyboard.target = .none
        }
    }

    private func navigate() {
        var text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") {
            text = "https://" + text
        }
        guard let url = URL(string: text) else { return }
        pendingLoadURL = url
        navigationToken = UUID()
        keyboard.target = .none
        HapticsManager.appOpen()
    }

    private func reload() {
        navigationToken = UUID()
        HapticsManager.tap()
    }
}

/// Thin UIViewRepresentable wrapper so Safari acts like a real, live browser.
private struct WebContainerView: UIViewRepresentable {
    let url: URL?
    let navigationToken: UUID
    let backToken: UUID
    let forwardToken: UUID
    @Binding var isLoading: Bool
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var resolvedAddress: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        if let url {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastToken != navigationToken, let url {
            context.coordinator.lastToken = navigationToken
            webView.load(URLRequest(url: url))
        }
        if context.coordinator.lastBackToken != backToken {
            context.coordinator.lastBackToken = backToken
            webView.goBack()
        }
        if context.coordinator.lastForwardToken != forwardToken {
            context.coordinator.lastForwardToken = forwardToken
            webView.goForward()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebContainerView
        var lastToken: UUID?
        var lastBackToken: UUID?
        var lastForwardToken: UUID?

        init(_ parent: WebContainerView) {
            self.parent = parent
            self.lastBackToken = parent.backToken
            self.lastForwardToken = parent.forwardToken
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            if let host = webView.url?.absoluteString {
                parent.resolvedAddress = host
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
