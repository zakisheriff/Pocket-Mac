import Foundation
import Network

enum RFBError: LocalizedError, Equatable {
    case connectionClosed
    case connectionFailed(String)
    case unsupportedVersion(String)
    case noSupportedSecurityType([UInt8])
    case authenticationFailed(String)
    case serverRefused(String)
    case protocolViolation(String)
    case unsupportedEncoding(Int32)

    var errorDescription: String? {
        switch self {
        case .connectionClosed:
            return "The Mac closed the connection."
        case .connectionFailed(let reason):
            return "Couldn't reach your Mac. Check that it's awake with Screen Sharing on, that both are on the same Wi‑Fi, and that Local Network is allowed for Pocket Mac in Settings › Privacy & Security. (\(reason))"
        case .unsupportedVersion(let version):
            return "This Mac speaks an unsupported Screen Sharing version (\(version))."
        case .noSupportedSecurityType(let types):
            return "The Mac didn't offer a login method Pocket Mac supports (offered: \(types.map(String.init).joined(separator: ", ")))."
        case .authenticationFailed(let reason):
            let hint = "Check your Mac username (the short account name) and password, and that your account is allowed under System Settings › General › Sharing › Screen Sharing ⓘ."
            return reason.isEmpty ? hint : "\(reason). \(hint)"
        case .serverRefused(let reason):
            return reason
        case .protocolViolation(let detail):
            return "Unexpected data from the Mac: \(detail)"
        case .unsupportedEncoding(let encoding):
            return "The Mac sent screen data in an unsupported format (\(encoding))."
        }
    }
}

/// An ordered byte stream to the Mac's Screen Sharing (VNC/RFB) server.
///
/// Reads are only ever issued by the single session loop; writes go through
/// `enqueue`, which Network.framework delivers in call order, so input events
/// can be sent from the main thread while a large screen update is still
/// being read.
actor RFBStream {
    /// Ways to reach the Mac, tried in order (e.g. Bonjour, then its last
    /// known Wi‑Fi address).
    private let endpoints: [NWEndpoint]
    private let attemptTimeout: TimeInterval
    private let current = ConnectionBox()
    private let queue = DispatchQueue(label: "com.zakisheriff.pocketmac.rfb", qos: .userInteractive)
    private var buffer = Data()
    private var readOffset = 0
    /// Every byte read so far, for the session's throughput stats.
    private(set) var totalBytesRead = 0

    init(endpoints: [NWEndpoint], attemptTimeout: TimeInterval = 6) {
        precondition(!endpoints.isEmpty, "need at least one way to reach the Mac")
        self.endpoints = endpoints
        self.attemptTimeout = attemptTimeout
    }

    init(endpoint: NWEndpoint) {
        self.init(endpoints: [endpoint])
    }

    /// Connects using the first route that works. Each route gets its own
    /// time limit, so one that never answers (a Bonjour name resolving to an
    /// interface that doesn't route) can't leave the app spinning forever.
    func open() async throws {
        var lastError: Error = RFBError.connectionFailed("timed out")
        for (endpoint, wifiOnly) in attempts {
            try Task.checkCancellation()
            let connection = Self.makeConnection(to: endpoint, wifiOnly: wifiOnly)
            do {
                try await Self.start(connection, on: queue, timeout: attemptTimeout)
                current.set(connection)
                return
            } catch {
                connection.cancel()
                lastError = error
            }
        }
        throw lastError
    }

    /// Bonjour names are tried as-is and then pinned to Wi‑Fi, in case the
    /// system picked an interface (like a cable link) that doesn't route.
    private var attempts: [(NWEndpoint, Bool)] {
        endpoints.flatMap { endpoint -> [(NWEndpoint, Bool)] in
            if case .service = endpoint { return [(endpoint, false), (endpoint, true)] }
            return [(endpoint, false)]
        }
    }

    /// The address that actually answered, so it can be tried directly next time.
    nonisolated var reachedAddress: (host: String, port: UInt16)? {
        guard case .hostPort(let host, let port) = current.get()?.currentPath?.remoteEndpoint else { return nil }
        switch host {
        case .ipv4(let address): return ("\(address)", port.rawValue)
        case .name(let name, _): return (name, port.rawValue)
        default: return nil
        }
    }

    nonisolated func close() {
        current.get()?.cancel()
    }

    nonisolated func enqueue(_ data: Data) {
        current.get()?.send(content: data, completion: .idempotent)
    }

    private static func makeConnection(to endpoint: NWEndpoint, wifiOnly: Bool) -> NWConnection {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 6
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        if wifiOnly { parameters.requiredInterfaceType = .wifi }
        return NWConnection(to: endpoint, using: parameters)
    }

    private static func start(_ connection: NWConnection, on queue: DispatchQueue, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(.success(()))
                case .failed(let error), .waiting(let error):
                    once.resume(.failure(RFBError.connectionFailed(error.localizedDescription)))
                case .cancelled:
                    once.resume(.failure(RFBError.connectionClosed))
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                once.resume(.failure(RFBError.connectionFailed("timed out")))
            }
            connection.start(queue: queue)
        }
    }

    func read(_ count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        while buffer.count - readOffset < count {
            let needed = count - (buffer.count - readOffset)
            let chunk = try await receive(maximum: max(needed, 256 * 1024))
            buffer.append(chunk)
        }
        let start = buffer.startIndex + readOffset
        let result = buffer.subdata(in: start..<(start + count))
        readOffset += count
        totalBytesRead += count
        if readOffset > 1 << 20 || readOffset == buffer.count {
            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + readOffset))
            readOffset = 0
        }
        return result
    }

    func readU8() async throws -> UInt8 {
        try await read(1)[0]
    }

    func readU16() async throws -> UInt16 {
        try await read(2).bigEndianU16(at: 0)
    }

    func readU32() async throws -> UInt32 {
        try await read(4).bigEndianU32(at: 0)
    }

    func readS32() async throws -> Int32 {
        Int32(bitPattern: try await readU32())
    }

    private func receive(maximum: Int) async throws -> Data {
        guard let connection = current.get() else { throw RFBError.connectionClosed }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximum) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: RFBError.connectionFailed(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(throwing: RFBError.connectionClosed)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

/// The live connection, readable from any thread (input is sent off the actor).
private final class ConnectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var connection: NWConnection?

    func set(_ connection: NWConnection) { lock.withLock { self.connection = connection } }
    func get() -> NWConnection? { lock.withLock { connection } }
}

/// Resumes a continuation exactly once, whichever of ready / failure /
/// timeout happens first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }

    func resume(_ result: Result<Void, Error>) {
        let pending: CheckedContinuation<Void, Error>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}

extension Data {
    func bigEndianU16(at offset: Int) -> UInt16 {
        let i = startIndex + offset
        return UInt16(self[i]) << 8 | UInt16(self[i + 1])
    }

    func bigEndianU32(at offset: Int) -> UInt32 {
        let i = startIndex + offset
        return UInt32(self[i]) << 24 | UInt32(self[i + 1]) << 16 | UInt32(self[i + 2]) << 8 | UInt32(self[i + 3])
    }

    mutating func appendBE(_ value: UInt16) {
        append(UInt8(value >> 8))
        append(UInt8(value & 0xff))
    }

    mutating func appendBE(_ value: UInt32) {
        append(UInt8(value >> 24))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8(value & 0xff))
    }

    mutating func appendBE(_ value: Int32) {
        appendBE(UInt32(bitPattern: value))
    }
}
