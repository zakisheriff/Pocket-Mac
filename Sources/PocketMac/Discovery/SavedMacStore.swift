import Foundation
import Network

/// A Mac the user has connected to before. The password is kept in the
/// Keychain under `id`, never in this record.
struct SavedMac: Identifiable, Codable, Hashable {
    enum Address: Codable, Hashable {
        /// Found over Bonjour; reconnects by service name even if its IP changes.
        case bonjour(serviceName: String)
        /// Typed in by hand.
        case host(String, port: UInt16)
    }

    var id = UUID()
    var name: String
    var address: Address
    var username: String
    /// The IP that last answered, tried if Bonjour can't reach the Mac.
    var lastKnownHost: String?
    var lastKnownPort: UInt16?

    var endpoint: NWEndpoint {
        switch address {
        case .bonjour(let serviceName):
            return .service(name: serviceName, type: "_rfb._tcp", domain: "local.", interface: nil)
        case .host(let host, let port):
            return .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 5900)
        }
    }

    var fallbackEndpoints: [NWEndpoint] {
        guard case .bonjour = address, let host = lastKnownHost else { return [] }
        return [.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: lastKnownPort ?? 5900) ?? 5900)]
    }

    var subtitle: String {
        switch address {
        case .bonjour: return username.isEmpty ? "On this network" : "\(username) · On this network"
        case .host(let host, let port):
            let place = port == 5900 ? host : "\(host):\(port)"
            return username.isEmpty ? place : "\(username) · \(place)"
        }
    }
}

@MainActor
final class SavedMacStore: ObservableObject {
    @Published private(set) var macs: [SavedMac] = []

    private let defaults: UserDefaults
    private let storageKey = "pocketmac.savedMacs"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([SavedMac].self, from: data) {
            macs = decoded
        }
    }

    func password(for mac: SavedMac) -> String? {
        KeychainStore.password(for: mac.id.uuidString)
    }

    /// Adds or updates a Mac, matching on its address so reconnecting to the
    /// same Mac doesn't create duplicates.
    @discardableResult
    func save(name: String, address: SavedMac.Address, username: String, password: String?) -> SavedMac {
        var mac: SavedMac
        if let index = macs.firstIndex(where: { $0.address == address }) {
            macs[index].name = name
            macs[index].username = username
            mac = macs[index]
            macs.remove(at: index)
        } else {
            mac = SavedMac(name: name, address: address, username: username)
        }
        macs.insert(mac, at: 0)
        if let password {
            KeychainStore.setPassword(password, for: mac.id.uuidString)
        } else {
            KeychainStore.deletePassword(for: mac.id.uuidString)
        }
        persist()
        return mac
    }

    func recordReachedAddress(_ host: String, port: UInt16, for id: UUID) {
        guard let index = macs.firstIndex(where: { $0.id == id }) else { return }
        guard macs[index].lastKnownHost != host || macs[index].lastKnownPort != port else { return }
        macs[index].lastKnownHost = host
        macs[index].lastKnownPort = port
        persist()
    }

    /// A connection request that tries Bonjour first, then the last address
    /// that worked, and remembers whichever answers.
    func request(for mac: SavedMac, password: String) -> MacConnectionRequest {
        MacConnectionRequest(
            endpoint: mac.endpoint,
            fallbacks: mac.fallbackEndpoints,
            displayName: mac.name,
            username: mac.username,
            password: password,
            onReachedAddress: { [weak self] host, port in
                self?.recordReachedAddress(host, port: port, for: mac.id)
            }
        )
    }

    func remove(_ mac: SavedMac) {
        macs.removeAll { $0.id == mac.id }
        KeychainStore.deletePassword(for: mac.id.uuidString)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(macs) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
