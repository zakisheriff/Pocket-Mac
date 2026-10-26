import CoreGraphics
import Foundation
import IOSurface
import Network
import OSLog
import UIKit

/// Where and how to log in to a Mac.
struct MacConnectionRequest {
    /// Routes to the Mac, tried in order until one answers.
    var endpoints: [NWEndpoint]
    var displayName: String
    var username: String
    var password: String
    /// Told the address that actually worked, so it can be remembered.
    var onReachedAddress: (@MainActor (String, UInt16) -> Void)?

    init(
        endpoint: NWEndpoint,
        fallbacks: [NWEndpoint] = [],
        displayName: String,
        username: String,
        password: String,
        onReachedAddress: (@MainActor (String, UInt16) -> Void)? = nil
    ) {
        endpoints = [endpoint] + fallbacks
        self.displayName = displayName
        self.username = username
        self.password = password
        self.onReachedAddress = onReachedAddress
    }
}

/// Receives the live screen and pointer directly, bypassing SwiftUI so
/// frames and pointer movement never wait on a view re-render.
@MainActor
protocol RemoteDisplaySink: AnyObject {
    /// The framebuffer to show (a new one after connecting or a resize).
    func display(surface: IOSurface?, size: CGSize)
    /// The framebuffer's pixels changed; redraw.
    func frameUpdated()
    func pointerMoved(to point: CGPoint)
    func cursorChanged(_ cursor: RFBCursor?)
}

/// A live Screen Sharing session with one Mac.
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
    @Published private(set) var hasScreen = false
    @Published private(set) var screenSize: CGSize = .zero
    @Published private(set) var desktopName = ""

    /// Pointer position in the Mac's screen coordinates. Not published:
    /// it changes at touch rate and goes straight to the display sink.
    private(set) var pointer: CGPoint = .zero
    private(set) var cursor: RFBCursor?
    private(set) var buttons: RFBButtons = []

    /// Every on-screen view showing this Mac, held weakly. Layout changes can
    /// briefly create a second view; each one gets every frame, so none is
    /// ever left showing a black screen.
    private let displays = NSHashTable<AnyObject>.weakObjects()

    private var sinks: [RemoteDisplaySink] {
        displays.allObjects.compactMap { $0 as? RemoteDisplaySink }
    }

    func addDisplay(_ sink: RemoteDisplaySink) {
        guard !displays.contains(sink) else { return }
        displays.add(sink)
        sink.display(surface: framebuffer?.surface, size: screenSize)
        if hasScreen { sink.frameUpdated() }
        sink.cursorChanged(cursor)
        sink.pointerMoved(to: pointer)
    }

    func removeDisplay(_ sink: RemoteDisplaySink) {
        displays.remove(sink)
    }

    private var stream: RFBStream?
    private var sessionTask: Task<Void, Never>?
    private var framebuffer: RFBFramebuffer?

    var isActive: Bool {
        state == .connecting || state == .authenticating || state == .connected
    }

    /// The session screen stays up for failures too, so the error can be
    /// read and retried instead of flashing past as the screen closes.
    var showsSession: Bool {
        if case .failed = state { return true }
        return isActive
    }

    private var lastRequest: MacConnectionRequest?

    func retry() {
        guard let lastRequest else { return }
        connect(lastRequest)
    }

    func connect(_ request: MacConnectionRequest) {
        lastRequest = request
        disconnect(newState: .connecting)
        let stream = RFBStream(endpoints: request.endpoints)
        self.stream = stream
        hasScreen = false
        cursor = nil
        framebuffer = nil
        for sink in sinks {
            sink.display(surface: nil, size: .zero)
            sink.cursorChanged(nil)
        }

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

    func acknowledgeFailure() {
        if case .failed = state { state = .idle }
    }

    private func disconnect(newState: State) {
        sessionTask?.cancel()
        sessionTask = nil
        stream?.close()
        stream = nil
        buttons = []
        state = newState
    }

    /// A copy of the current screen (for tests and snapshots).
    func snapshot() -> CGImage? {
        framebuffer?.makeImage()
    }

    // MARK: - Input

    func movePointer(to point: CGPoint) {
        guard screenSize != .zero else { return }
        let clamped = CGPoint(
            x: min(max(point.x, 0), screenSize.width - 1),
            y: min(max(point.y, 0), screenSize.height - 1)
        )
        pointer = clamped
        for sink in sinks { sink.pointerMoved(to: clamped) }
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

    /// macOS samples the mouse button state rather than replaying every
    /// event, so a press released in the same instant can be missed. Hold the
    /// button briefly, like a real click, and keep modifiers down until after.
    func click(_ button: RFBButtons = .left, modifiers: Set<ModifierKey> = []) {
        let ordered = ModifierKey.allCases.filter(modifiers.contains)
        for modifier in ordered { sendKey(modifier.keysym, down: true) }
        press(button)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clickHoldDuration) { [weak self] in
            self?.release(button)
            for modifier in ordered.reversed() { self?.sendKey(modifier.keysym, down: false) }
        }
    }

    static let clickHoldDuration: TimeInterval = 0.06

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

    fileprivate func sessionStarted(stream: RFBStream, name: String, framebuffer: RFBFramebuffer) {
        guard stream === self.stream else { return }
        desktopName = name
        self.framebuffer = framebuffer
        shownSurface = framebuffer.surface
        screenSize = CGSize(width: framebuffer.width, height: framebuffer.height)
        pointer = CGPoint(x: screenSize.width / 2, y: screenSize.height / 2)
        for sink in sinks {
            sink.display(surface: framebuffer.surface, size: screenSize)
            sink.pointerMoved(to: pointer)
        }
        state = .connected
    }

    fileprivate func framebufferUpdated(stream: RFBStream) {
        guard stream === self.stream, let framebuffer else { return }
        let size = CGSize(width: framebuffer.width, height: framebuffer.height)
        let surfaceChanged = framebuffer.surface !== shownSurface
        if size != screenSize {
            screenSize = size
            movePointer(to: pointer)
        }
        if surfaceChanged {
            shownSurface = framebuffer.surface
            for sink in sinks { sink.display(surface: framebuffer.surface, size: size) }
        }
        if !hasScreen { hasScreen = true }
        for sink in sinks { sink.frameUpdated() }
    }

    /// The surface the displays were last given (it changes on resize).
    private var shownSurface: IOSurface?

    fileprivate func cursorChanged(stream: RFBStream, cursor newCursor: RFBCursor) {
        guard stream === self.stream else { return }
        cursor = newCursor
        for sink in sinks { sink.cursorChanged(newCursor) }
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

/// Prints how the session is performing to the Xcode console every couple of
/// seconds: frames per second, data rate and which screen formats the Mac
/// chose — the numbers needed to tell where any lag comes from.
private struct SessionStats {
    private static let log = Logger(subsystem: "com.zakisheriff.pocketmac", category: "session")
    var screenSize = ""
    private var frames = 0
    private var bytes = 0
    private var bytesByEncoding: [Int32: Int] = [:]
    private var windowStart = Date()

    mutating func record(encoding: Int32, bytes count: Int) {
        bytes += count
        bytesByEncoding[encoding, default: 0] += count
    }

    mutating func frameDone() {
        frames += 1
        let elapsed = Date().timeIntervalSince(windowStart)
        guard elapsed >= 2 else { return }
        let fps = Double(frames) / elapsed
        let rate = Double(bytes) / elapsed / 1_048_576
        let mix = bytesByEncoding.sorted { $0.value > $1.value }.map { encoding, count in
            "\(Self.name(encoding)) \(bytes > 0 ? count * 100 / bytes : 0)%"
        }.joined(separator: ", ")
        let line = String(format: "Pocket Mac: %.1f fps · %.2f MB/s · screen %@ · %@", fps, rate, screenSize, mix)
        Self.log.notice("\(line, privacy: .public)")
        print(line)
        frames = 0
        bytes = 0
        bytesByEncoding = [:]
        windowStart = Date()
    }

    private static func name(_ encoding: Int32) -> String {
        switch encoding {
        case RFBEncoding.raw: return "raw"
        case RFBEncoding.copyRect: return "copyrect"
        case RFBEncoding.hextile: return "hextile"
        case RFBEncoding.zlib: return "zlib"
        case RFBEncoding.zrle: return "zrle"
        case RFBEncoding.cursor: return "cursor"
        case RFBEncoding.desktopSize: return "resize"
        default: return "enc \(encoding)"
        }
    }
}

/// At most one frame in flight to the main thread.
private final class FrameGate: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false

    func claim() -> Bool {
        lock.withLock {
            guard !pending else { return false }
            pending = true
            return true
        }
    }

    func release() {
        lock.withLock { pending = false }
    }
}

/// Runs the RFB protocol for one connection off the main thread.
private final class RFBSession {
    private let stream: RFBStream
    private let request: MacConnectionRequest
    private weak var client: RFBClient?
    private var framebuffer = RFBFramebuffer(width: 0, height: 0)
    private let zrle = ZRLEDecoder()
    private let zlibRects = ZlibRectDecoder()
    private let frameGate = FrameGate()
    private var stats = SessionStats()

    init(stream: RFBStream, request: MacConnectionRequest, client: RFBClient?) {
        self.stream = stream
        self.request = request
        self.client = client
    }

    /// Fire-and-forget hop to the main thread: the receive loop never waits
    /// for the UI, so a busy main thread can't slow the screen stream.
    private func onMain(_ work: @escaping @MainActor (RFBClient) -> Void) {
        let client = self.client
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let client { work(client) }
            }
        }
    }

    func run() async throws {
        try await stream.open()
        let stream = self.stream
        onMain { $0.update(state: .authenticating, for: stream) }
        if let reached = stream.reachedAddress, let remember = request.onReachedAddress {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { remember(reached.host, reached.port) }
            }
        }

        try await handshake()

        stream.enqueue(Data([1])) // ClientInit: share the screen with other viewers
        let width = Int(try await stream.readU16())
        let height = Int(try await stream.readU16())
        _ = try await stream.read(16) // server's native pixel format; we ask for our own below
        let nameLength = Int(try await stream.readU32())
        let name = String(decoding: try await stream.read(nameLength), as: UTF8.self)

        let framebuffer = RFBFramebuffer(width: width, height: height)
        self.framebuffer = framebuffer
        stream.enqueue(RFBClientMessage.setPixelFormat(.bgrx))
        // Most compact first; the Mac picks the first one it supports.
        stream.enqueue(RFBClientMessage.setEncodings([
            RFBEncoding.zrle, RFBEncoding.zlib, RFBEncoding.hextile,
            RFBEncoding.copyRect, RFBEncoding.raw,
            RFBEncoding.cursor, RFBEncoding.desktopSize,
        ]))
        stats.screenSize = "\(width)x\(height)"
        requestUpdate(incremental: false)
        let displayName = name.isEmpty ? request.displayName : name
        onMain { $0.sessionStarted(stream: stream, name: displayName, framebuffer: framebuffer) }

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
        let stream = self.stream
        switch type {
        case 0:
            try await readFramebufferUpdate()
        case 1:
            _ = try await stream.read(3)
            let count = Int(try await stream.readU16())
            _ = try await stream.read(count * 6)
        case 2:
            DispatchQueue.main.async { HapticsManager.tap() }
        case 3:
            _ = try await stream.read(3)
            let length = Int(try await stream.readU32())
            let text = String(data: try await stream.read(length), encoding: .isoLatin1) ?? ""
            onMain { $0.receivedClipboard(stream: stream, text: text) }
        default:
            throw RFBError.protocolViolation("unknown server message \(type)")
        }
    }

    private func readFramebufferUpdate() async throws {
        _ = try await stream.readU8()
        let rectangles = Int(try await stream.readU16())
        let stream = self.stream

        // Ask for the next frame now, so the Mac prepares it while this one
        // is still downloading and decoding — removes a full round trip.
        requestUpdate(incremental: true)

        for _ in 0..<rectangles {
            let x = Int(try await stream.readU16())
            let y = Int(try await stream.readU16())
            let width = Int(try await stream.readU16())
            let height = Int(try await stream.readU16())
            let encoding = try await stream.readS32()
            let bytesBefore = await stream.totalBytesRead

            switch encoding {
            case RFBEncoding.raw:
                let pixels = try await stream.read(width * height * 4)
                try framebuffer.blitRaw(x: x, y: y, width: width, height: height, data: pixels)
            case RFBEncoding.copyRect:
                let sourceX = Int(try await stream.readU16())
                let sourceY = Int(try await stream.readU16())
                try framebuffer.copyRect(fromX: sourceX, fromY: sourceY, toX: x, toY: y, width: width, height: height)
            case RFBEncoding.zrle:
                let length = Int(try await stream.readU32())
                let compressed = try await stream.read(length)
                try zrle.decode(x: x, y: y, width: width, height: height, compressed: compressed, into: framebuffer)
            case RFBEncoding.zlib:
                let length = Int(try await stream.readU32())
                let compressed = try await stream.read(length)
                try zlibRects.decode(x: x, y: y, width: width, height: height, compressed: compressed, into: framebuffer)
            case RFBEncoding.hextile:
                try await HextileDecoder.decode(x: x, y: y, width: width, height: height, from: stream, into: framebuffer)
            case RFBEncoding.cursor:
                let pixels = try await stream.read(width * height * 4)
                let mask = try await stream.read(((width + 7) / 8) * height)
                if let cursor = RFBCursor(width: width, height: height, hotspotX: x, hotspotY: y, pixels: pixels, mask: mask) {
                    onMain { $0.cursorChanged(stream: stream, cursor: cursor) }
                }
            case RFBEncoding.desktopSize:
                framebuffer.resize(width: width, height: height)
            default:
                throw RFBError.unsupportedEncoding(encoding)
            }
            stats.record(encoding: encoding, bytes: await stream.totalBytesRead - bytesBefore)
        }

        stats.frameDone()
        publishFrame()
    }

    /// Shows the latest frame. If the display hasn't caught up with the
    /// previous one yet, this frame is folded into it rather than queued —
    /// the screen always shows the newest pixels, never a backlog.
    private func publishFrame() {
        guard frameGate.claim() else { return }
        let stream = self.stream
        let gate = frameGate
        onMain { client in
            gate.release()
            client.framebufferUpdated(stream: stream)
        }
    }

    private func requestUpdate(incremental: Bool) {
        stream.enqueue(RFBClientMessage.framebufferUpdateRequest(
            incremental: incremental, x: 0, y: 0,
            width: UInt16(framebuffer.width), height: UInt16(framebuffer.height)
        ))
    }
}
