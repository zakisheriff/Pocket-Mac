import Foundation
import BigInt
@testable import Pocket_Mac

/// A minimal Screen Sharing server for integration tests. It greets like
/// macOS (`RFB 003.889`), offers Apple and VNC logins, verifies credentials,
/// sends one raw screen update and records the input it receives.
final class FakeRFBServer {
    enum Login {
        case vncPassword(String)
        case macAccount(username: String, password: String)
    }

    struct PointerEvent: Equatable {
        let buttons: UInt8
        let x: UInt16
        let y: UInt16
    }

    struct KeyEvent: Equatable {
        let keysym: UInt32
        let down: Bool
    }

    let port: UInt16
    private let listenSocket: Int32
    private let login: Login
    private let width: Int
    private let height: Int
    private let pixels: [UInt32]
    private let lock = NSLock()
    private var _pointerEvents: [PointerEvent] = []
    private var _keyEvents: [KeyEvent] = []
    private var _requestedEncodings: [Int32] = []
    private var _updateRequests = 0
    private var _pointerTimes: [Date] = []

    var pointerEvents: [PointerEvent] { lock.withLock { _pointerEvents } }
    var keyEvents: [KeyEvent] { lock.withLock { _keyEvents } }
    var requestedEncodings: [Int32] { lock.withLock { _requestedEncodings } }
    var updateRequests: Int { lock.withLock { _updateRequests } }
    var pointerTimes: [Date] { lock.withLock { _pointerTimes } }

    init(login: Login, width: Int, height: Int, pixels: [UInt32]) throws {
        precondition(pixels.count == width * height)
        self.login = login
        self.width = width
        self.height = height
        self.pixels = pixels

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else {
            close(fd)
            throw NSError(domain: "FakeRFBServer", code: Int(errno))
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(fd, $0, &length)
            }
        }
        listenSocket = fd
        port = UInt16(bigEndian: address.sin_port)
    }

    deinit {
        close(listenSocket)
    }

    func start() {
        Thread { [self] in
            let client = accept(listenSocket, nil, nil)
            guard client >= 0 else { return }
            serve(client)
            close(client)
        }.start()
    }

    // MARK: - Script

    private func serve(_ fd: Int32) {
        send(fd, Data("RFB 003.889\n".utf8))
        guard let version = read(fd, 12), String(decoding: version, as: UTF8.self) == "RFB 003.008\n" else { return }

        send(fd, Data([2, 30, 2]))
        guard let chosen = read(fd, 1)?.first else { return }

        let accepted: Bool
        switch (login, chosen) {
        case (.vncPassword(let password), 2):
            let challenge = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
            send(fd, challenge)
            guard let answer = read(fd, 16) else { return }
            accepted = answer == VNCPasswordAuth.response(challenge: challenge, password: password)

        case (.macAccount(let username, let password), 30):
            let secret = BigUInt(0xC0FFEE_1234_5678)
            let serverPublic = BigUInt(2).power(secret, modulus: TestDH.prime)
            var challenge = Data()
            challenge.appendBE(UInt16(2))
            challenge.appendBE(UInt16(128))
            challenge.append(AppleRemoteDesktopAuth.leftPad(TestDH.prime.serialize(), to: 128))
            challenge.append(AppleRemoteDesktopAuth.leftPad(serverPublic.serialize(), to: 128))
            send(fd, challenge)
            guard let answer = read(fd, 256) else { return }
            let response = AppleRemoteDesktopAuth.Response(
                encryptedCredentials: answer.prefix(128), clientPublicKey: answer.suffix(128)
            )
            let credentials = TestDH.decryptCredentials(response, serverSecret: secret)
            accepted = credentials.username == username && credentials.password == password

        default:
            accepted = false
        }

        var result = Data()
        result.appendBE(UInt32(accepted ? 0 : 1))
        if !accepted {
            let reason = Data("Authentication failed".utf8)
            result.appendBE(UInt32(reason.count))
            result.append(reason)
            send(fd, result)
            return
        }
        send(fd, result)

        guard read(fd, 1) != nil else { return } // ClientInit
        var serverInit = Data()
        serverInit.appendBE(UInt16(width))
        serverInit.appendBE(UInt16(height))
        serverInit.append(RFBPixelFormat.bgrx.encoded)
        let name = Data("Fake Mac".utf8)
        serverInit.appendBE(UInt32(name.count))
        serverInit.append(name)
        send(fd, serverInit)

        var sentScreen = false
        while let type = read(fd, 1)?.first {
            switch type {
            case 0:
                guard read(fd, 19) != nil else { return }
            case 2:
                guard let header = read(fd, 3) else { return }
                let count = Int(header.bigEndianU16(at: 1))
                guard let list = read(fd, count * 4) else { return }
                let encodings = (0..<count).map { Int32(bitPattern: list.bigEndianU32(at: $0 * 4)) }
                lock.withLock { _requestedEncodings = encodings }
            case 3:
                guard read(fd, 9) != nil else { return }
                lock.withLock { _updateRequests += 1 }
                if !sentScreen {
                    sentScreen = true
                    send(fd, rawScreenUpdate())
                }
            case 4:
                guard let body = read(fd, 7) else { return }
                let event = KeyEvent(keysym: body.bigEndianU32(at: 3), down: body[body.startIndex] != 0)
                lock.withLock { _keyEvents.append(event) }
            case 5:
                guard let body = read(fd, 5) else { return }
                let event = PointerEvent(buttons: body[body.startIndex], x: body.bigEndianU16(at: 1), y: body.bigEndianU16(at: 3))
                lock.withLock {
                    _pointerEvents.append(event)
                    _pointerTimes.append(Date())
                }
            case 6:
                guard let header = read(fd, 7) else { return }
                guard read(fd, Int(header.bigEndianU32(at: 3))) != nil else { return }
            default:
                return
            }
        }
    }

    private func rawScreenUpdate() -> Data {
        var data = Data([0, 0])
        data.appendBE(UInt16(1))
        data.appendBE(UInt16(0))
        data.appendBE(UInt16(0))
        data.appendBE(UInt16(width))
        data.appendBE(UInt16(height))
        data.appendBE(RFBEncoding.raw)
        for pixel in pixels {
            data.append(contentsOf: withUnsafeBytes(of: pixel.littleEndian, Array.init))
        }
        return data
    }

    // MARK: - Socket helpers

    private func send(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let sent = Darwin.send(fd, buffer.baseAddress! + offset, buffer.count - offset, 0)
                if sent <= 0 { return }
                offset += sent
            }
        }
    }

    private func read(_ fd: Int32, _ count: Int) -> Data? {
        var data = Data(count: count)
        var offset = 0
        while offset < count {
            let received = data.withUnsafeMutableBytes { recv(fd, $0.baseAddress! + offset, count - offset, 0) }
            if received <= 0 { return nil }
            offset += received
        }
        return data
    }
}
