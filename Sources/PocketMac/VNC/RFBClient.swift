import CoreGraphics
import Foundation
import Network
import UIKit

/// Where and how to log in to a Mac.
struct MacConnectionRequest {
    var endpoint: NWEndpoint
    var displayName: String
    var username: String
    var password: String
}

/// A live Screen Sharing session with one Mac. Publishes the Mac's screen
/// and pointer shape for the UI and sends mouse/keyboard input back.
@MainActor
final class RFBClient: ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case authenticating
        case connected
        case failed(String)
        case disconnected
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var screen: CGImage?
    @Published private(set) var screenSize: CGSize = .zero
    @Published private(set) var desktopName = ""
    @Published private(set) var cursor: RFBCursor?

    /// Pointer position in the Mac's screen coordinates.
    @Published private(set) var pointer: CGPoint = .zero
    private(set) var buttons: RFBButtons = []

    private var stream: RFBStream?
    private var sessionTask: Task<Void, Never>?

    var isActive: Bool {
        state == .connecting || state == .authenticating || state == .connected
    }

    func connect(_ request: MacConnectionRequest) {
        disconnect(newState: .connecting)
        let stream = RFBStream(endpoint: request.endpoint)
        self.stream = stream
        screen = nil
        cursor = nil

        sessionTask = Task.detached(priority: .userInitiated) { [weak self] in
            let session = RFBSession(stream: stream, request: request, client: self)
            do {
                try await session.run()
            } catch is CancellationError {
                return
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await self?.sessionEnded(stream: stream, state: .failed(message))
                return
            }
            await self?.sessionEnded(stream: stream, state: .disconnected)
        }
    }

    func disconnect() {
        disconnect(newState: .disconnected)
    }

    private func disconnect(newState: State) {
        sessionTask?.cancel()
        sessionTask = nil
        stream?.close()
        stream = nil
        buttons = []
        state = newState
    }

    // MARK: - Input

    func movePointer(to point: CGPoint) {
        guard screenSize != .zero else { return }
        pointer = CGPoint(
            x: min(max(point.x, 0), screenSize.width - 1),
            y: min(max(point.y, 0), screenSize.height - 1)
        )
        sendPointer()
    }

    func movePointer(by delta: CGVector) {
        movePointer(to: CGPoint(x: pointer.x + delta.dx, y: pointer.y + delta.dy))
    }

    func press(_ button: RFBButtons) {
        buttons.insert(button)
        sendPointer()
    }

    func release(_ button: RFBButtons) {
        buttons.remove(button)
        sendPointer()
    }

    func click(_ button: RFBButtons = .left, count: Int = 1) {
        for _ in 0..<count {
            press(button)
            release(button)
        }
    }

    /// Positive `steps` scrolls content up (wheel up), negative scrolls down.
    func scroll(vertical steps: Int, horizontal: Int = 0) {
        let verticalButton: RFBButtons = steps > 0 ? .wheelUp : .wheelDown
        for _ in 0..<abs(steps) { tap(wheel: verticalButton) }
        let horizontalButton: RFBButtons = horizontal > 0 ? .wheelLeft : .wheelRight
        for _ in 0..<abs(horizontal) { tap(wheel: horizontalButton) }
    }

    func sendKey(_ keysym: UInt32, down: Bool) {
        stream?.enqueue(RFBClientMessage.keyEvent(keysym: keysym, down: down))
    }

    func tapKey(_ keysym: UInt32, modifiers: Set<ModifierKey> = []) {
        let ordered = ModifierKey.allCases.filter(modifiers.contains)
        for modifier in ordered { sendKey(modifier.keysym, down: true) }
        sendKey(keysym, down: true)
        sendKey(keysym, down: false)
        for modifier in ordered.reversed() { sendKey(modifier.keysym, down: false) }
    }

    func type(_ text: String) {
        for character in text {
            if let keysym = Keysym.character(character) { tapKey(keysym) }
        }
    }

    func sendClipboard(_ text: String) {
        stream?.enqueue(RFBClientMessage.clientCutText(text))
    }

    private func tap(wheel: RFBButtons) {
        stream?.enqueue(RFBClientMessage.pointerEvent(buttons: buttons.union(wheel), x: UInt16(pointer.x), y: UInt16(pointer.y)))
        stream?.enqueue(RFBClientMessage.pointerEvent(buttons: buttons, x: UInt16(pointer.x), y: UInt16(pointer.y)))
    }

    private func sendPointer() {
        stream?.enqueue(RFBClientMessage.pointerEvent(buttons: buttons, x: UInt16(pointer.x), y: UInt16(pointer.y)))
    }

    // MARK: - Session callbacks

    fileprivate func update(state newState: State, for stream: RFBStream) {
        guard stream === self.stream else { return }
        state = newState
    }

    fileprivate func sessionStarted(stream: RFBStream, name: String, size: CGSize) {
        guard stream === self.stream else { return }
        desktopName = name
        screenSize = size
        pointer = CGPoint(x: size.width / 2, y: size.height / 2)
        state = .connected
    }

    fileprivate func publish(stream: RFBStream, image: CGImage?, size: CGSize, cursor newCursor: RFBCursor?) {
        guard stream === self.stream else { return }
        if size != screenSize {
            screenSize = size
            movePointer(to: pointer)
        }
        if let image { screen = image }
        if let newCursor { cursor = newCursor }
    }

    fileprivate func receivedClipboard(stream: RFBStream, text: String) {
        guard stream === self.stream, !text.isEmpty else { return }
        UIPasteboard.general.string = text
    }

    fileprivate func sessionEnded(stream: RFBStream, state newState: State) {
        guard stream === self.stream else { return }
        stream.close()
        self.stream = nil
        state = newState
    }
}

/// Runs the RFB protocol for one connection off the main thread.
private final class RFBSession {
    private let stream: RFBStream
    private let request: MacConnectionRequest
    private weak var client: RFBClient?
    private var framebuffer = RFBFramebuffer(width: 0, height: 0)
    private let zrle = ZRLEDecoder()

    init(stream: RFBStream, request: MacConnectionRequest, client: RFBClient?) {
        self.stream = stream
        self.request = request
        self.client = client
    }

    func run() async throws {
        try await stream.open()
        await client?.update(state: .authenticating, for: stream)

        try await handshake()

        stream.enqueue(Data([1])) // ClientInit: share the screen with other viewers
        let width = Int(try await stream.readU16())
        let height = Int(try await stream.readU16())
        _ = try await stream.read(16) // server's native pixel format; we ask for our own below
        let nameLength = Int(try await stream.readU32())
        let name = String(decoding: try await stream.read(nameLength), as: UTF8.self)

        framebuffer = RFBFramebuffer(width: width, height: height)
        stream.enqueue(RFBClientMessage.setPixelFormat(.bgrx))
        stream.enqueue(RFBClientMessage.setEncodings([
            RFBEncoding.zrle, RFBEncoding.copyRect, RFBEncoding.raw,
            RFBEncoding.cursor, RFBEncoding.desktopSize,
        ]))
        requestUpdate(incremental: false)
        await client?.sessionStarted(stream: stream, name: name.isEmpty ? request.displayName : name,
                                     size: CGSize(width: width, height: height))

        while !Task.isCancelled {
            try await readServerMessage()
        }
        throw CancellationError()
    }

    // MARK: Handshake

    private func handshake() async throws {
        let versionData = try await stream.read(12)
        let version = String(decoding: versionData, as: UTF8.self)
        guard version.hasPrefix("RFB "), let minor = Int(version.dropFirst(8).prefix(3)) else {
            throw RFBError.unsupportedVersion(version.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if minor < 7 {
            stream.enqueue(Data("RFB 003.003\n".utf8))
            let type = try await stream.readU32()
            if type == 0 { throw RFBError.serverRefused(try await readReason()) }
            try await authenticate(type: UInt8(truncatingIfNeeded: type), reportsReason: false)
            return
        }

        stream.enqueue(Data("RFB 003.008\n".utf8))
        let count = Int(try await stream.readU8())
        if count == 0 { throw RFBError.serverRefused(try await readReason()) }
        let offered = [UInt8](try await stream.read(count))
        let chosen = try chooseSecurityType(from: offered)
        stream.enqueue(Data([chosen]))
        try await authenticate(type: chosen, reportsReason: true)
    }

    private func chooseSecurityType(from offered: [UInt8]) throws -> UInt8 {
        let hasUsername = !request.username.isEmpty
        if hasUsername, offered.contains(30) { return 30 }
        if offered.contains(2) { return 2 }
        if offered.contains(30) { return 30 }
        if offered.contains(1) { return 1 }
        throw RFBError.noSupportedSecurityType(offered)
    }

    private func authenticate(type: UInt8, reportsReason: Bool) async throws {
        switch type {
        case 1:
            break
        case 2:
            let challenge = try await stream.read(16)
            stream.enqueue(VNCPasswordAuth.response(challenge: challenge, password: request.password))
        case 30:
            guard !request.username.isEmpty else {
                throw RFBError.authenticationFailed("This Mac needs your Mac username as well as your password.")
            }
            let generator = try await stream.readU16()
            let keyLength = Int(try await stream.readU16())
            let prime = try await stream.read(keyLength)
            let serverKey = try await stream.read(keyLength)
            let response = AppleRemoteDesktopAuth.response(
                to: .init(generator: generator, keyLength: keyLength, prime: prime, serverPublicKey: serverKey),
                username: request.username,
                password: request.password
            )
            stream.enqueue(response.encoded)
        default:
            throw RFBError.noSupportedSecurityType([type])
        }

        // Protocol 3.3/3.7 skip SecurityResult for "None"; 3.8 always sends it.
        if type == 1 && !reportsReason { return }
        let result = try await stream.readU32()
        guard result == 0 else {
            let reason = reportsReason ? (try? await readReason()) ?? "" : ""
            throw RFBError.authenticationFailed(reason)
        }
    }

    private func readReason() async throws -> String {
        let length = Int(try await stream.readU32())
        return String(decoding: try await stream.read(length), as: UTF8.self)
    }

    // MARK: Server messages

    private func readServerMessage() async throws {
        let type = try await stream.readU8()
        switch type {
        case 0:
            try await readFramebufferUpdate()
        case 1:
            _ = try await stream.read(3)
            let count = Int(try await stream.readU16())
            _ = try await stream.read(count * 6)
        case 2:
            await MainActor.run { HapticsManager.tap() }
        case 3:
            _ = try await stream.read(3)
            let length = Int(try await stream.readU32())
            let text = String(data: try await stream.read(length), encoding: .isoLatin1) ?? ""
            await client?.receivedClipboard(stream: stream, text: text)
        default:
            throw RFBError.protocolViolation("unknown server message \(type)")
        }
    }

    private func readFramebufferUpdate() async throws {
        _ = try await stream.readU8()
        let rectangles = Int(try await stream.readU16())
        var newCursor: RFBCursor?
        var screenChanged = false

        for _ in 0..<rectangles {
            let x = Int(try await stream.readU16())
            let y = Int(try await stream.readU16())
            let width = Int(try await stream.readU16())
            let height = Int(try await stream.readU16())
            let encoding = try await stream.readS32()

            switch encoding {
            case RFBEncoding.raw:
                let pixels = try await stream.read(width * height * 4)
                try framebuffer.blitRaw(x: x, y: y, width: width, height: height, data: pixels)
                screenChanged = true
            case RFBEncoding.copyRect:
                let sourceX = Int(try await stream.readU16())
                let sourceY = Int(try await stream.readU16())
                try framebuffer.copyRect(fromX: sourceX, fromY: sourceY, toX: x, toY: y, width: width, height: height)
                screenChanged = true
            case RFBEncoding.zrle:
                let length = Int(try await stream.readU32())
                let compressed = try await stream.read(length)
                try zrle.decode(x: x, y: y, width: width, height: height, compressed: compressed, into: framebuffer)
                screenChanged = true
            case RFBEncoding.cursor:
                let pixels = try await stream.read(width * height * 4)
                let mask = try await stream.read(((width + 7) / 8) * height)
                newCursor = RFBCursor(width: width, height: height, hotspotX: x, hotspotY: y, pixels: pixels, mask: mask)
            case RFBEncoding.desktopSize:
                framebuffer.resize(width: width, height: height)
                screenChanged = true
            default:
                throw RFBError.unsupportedEncoding(encoding)
            }
        }

        let image = screenChanged ? framebuffer.makeImage() : nil
        let size = CGSize(width: framebuffer.width, height: framebuffer.height)
        await client?.publish(stream: stream, image: image, size: size, cursor: newCursor)
        requestUpdate(incremental: true)
    }

    private func requestUpdate(incremental: Bool) {
        stream.enqueue(RFBClientMessage.framebufferUpdateRequest(
            incremental: incremental, x: 0, y: 0,
            width: UInt16(framebuffer.width), height: UInt16(framebuffer.height)
        ))
    }
}
