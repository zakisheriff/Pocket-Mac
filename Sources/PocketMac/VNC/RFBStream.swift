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
            return "Couldn't reach the Mac. Make sure Screen Sharing is on and both devices are on the same Wi‑Fi. (\(reason))"
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
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.zakisheriff.pocketmac.rfb", qos: .userInteractive)
    private var buffer = Data()
    private var readOffset = 0

    init(endpoint: NWEndpoint) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 10
        tcp.enableKeepalive = true
        connection = NWConnection(to: endpoint, using: NWParameters(tls: nil, tcp: tcp))
    }

    func open() async throws {
        let connection = self.connection
        let queue = self.queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            func finish(_ result: Result<Void, Error>) {
                guard !resumed else { return }
                resumed = true
                continuation.resume(with: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.success(()))
                case .failed(let error), .waiting(let error):
                    finish(.failure(RFBError.connectionFailed(error.localizedDescription)))
                    connection.cancel()
                case .cancelled:
                    finish(.failure(RFBError.connectionClosed))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    nonisolated func close() {
        connection.cancel()
    }

    nonisolated func enqueue(_ data: Data) {
        connection.send(content: data, completion: .idempotent)
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
        let connection = self.connection
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
