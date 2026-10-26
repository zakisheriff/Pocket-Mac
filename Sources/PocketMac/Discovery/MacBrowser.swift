import Foundation
import Network
import dnssd

/// Finds Macs on the local network that have Screen Sharing turned on —
/// macOS advertises them over Bonjour as `_rfb._tcp`.
@MainActor
final class MacBrowser: ObservableObject {
    struct DiscoveredMac: Identifiable, Hashable {
        let name: String
        let endpoint: NWEndpoint
        var id: String { name }
    }

    @Published private(set) var macs: [DiscoveredMac] = []
    @Published private(set) var isLocalNetworkDenied = false
    /// True for the first few seconds of a search, while new Macs usually appear.
    @Published private(set) var isScanning = false

    private var browser: NWBrowser?
    private var scanTask: Task<Void, Never>?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjour(type: "_rfb._tcp", domain: nil), using: .tcp)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { result -> DiscoveredMac? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return DiscoveredMac(name: name, endpoint: result.endpoint)
            }
            let unique = Dictionary(found.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            Task { @MainActor in
                self?.macs = unique.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            let denied: Bool
            switch state {
            case .waiting(let error), .failed(let error):
                denied = error == .dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))
            default:
                denied = false
            }
            Task { @MainActor in self?.isLocalNetworkDenied = denied }
        }

        browser.start(queue: .main)
        self.browser = browser
        markScanning()
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Starts a fresh search, as if the app had just opened.
    func refresh() async {
        stop()
        macs = []
        start()
        try? await Task.sleep(for: .seconds(2))
    }

    private func markScanning() {
        isScanning = true
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.isScanning = false
        }
    }
}
