import XCTest
import Network
@testable import Pocket_Mac

@MainActor
final class RFBClientIntegrationTests: XCTestCase {

    private let screenPixels: [UInt32] = [
        0xff0000, 0x00ff00, 0x0000ff,
        0xffffff, 0x000000, 0x808080,
    ]

    private func request(port: UInt16, username: String, password: String) -> MacConnectionRequest {
        MacConnectionRequest(
            endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
            displayName: "Test",
            username: username,
            password: password
        )
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("condition not met within \(timeout)s")
                throw NSError(domain: "RFBClientIntegrationTests.Timeout", code: 1)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func rgb(_ image: CGImage, x: Int, y: Int) -> UInt32 {
        let data = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16
    }

    func testMacAccountLoginStreamsTheScreenAndSendsInput() async throws {
        let server = try FakeRFBServer(login: .macAccount(username: "zaki", password: "s3cret!"), width: 3, height: 2, pixels: screenPixels)
        server.start()
        let client = RFBClient()
        client.connect(request(port: server.port, username: "zaki", password: "s3cret!"))

        do {
            try await waitUntil { client.hasScreen }
        } catch {
            XCTFail("never received the screen; state = \(client.state)")
            return
        }

        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(client.desktopName, "Fake Mac")
        XCTAssertEqual(client.screenSize, CGSize(width: 3, height: 2))
        let screen = try XCTUnwrap(client.snapshot())
        XCTAssertEqual(rgb(screen, x: 0, y: 0), 0xff0000)
        XCTAssertEqual(rgb(screen, x: 2, y: 1), 0x808080)

        XCTAssertEqual(server.requestedEncodings.first, RFBEncoding.copyRect)
        XCTAssertTrue(server.requestedEncodings.contains(RFBEncoding.zrle))
        XCTAssertTrue(server.requestedEncodings.contains(RFBEncoding.cursor))

        // The next frame is requested as soon as one arrives, not after it's drawn.
        try await waitUntil { server.updateRequests >= 2 }

        client.movePointer(to: CGPoint(x: 2, y: 1))
        client.click()
        try await waitUntil { server.pointerEvents.count >= 3 }
        XCTAssertEqual(Array(server.pointerEvents.suffix(3)), [
            .init(buttons: 0, x: 2, y: 1),
            .init(buttons: 1, x: 2, y: 1),
            .init(buttons: 0, x: 2, y: 1),
        ])
        // macOS samples the button state, so the press must be held briefly.
        let times = server.pointerTimes.suffix(2)
        XCTAssertGreaterThanOrEqual(times.last!.timeIntervalSince(times.first!), RFBClient.clickHoldDuration * 0.8)

        client.tapKey(0x61, modifiers: [.command])
        try await waitUntil { server.keyEvents.count >= 4 }
        XCTAssertEqual(server.keyEvents, [
            .init(keysym: Keysym.command, down: true),
            .init(keysym: 0x61, down: true),
            .init(keysym: 0x61, down: false),
            .init(keysym: Keysym.command, down: false),
        ])

        client.disconnect()
        XCTAssertEqual(client.state, .disconnected)
    }

    /// macOS can drop an update request (one arriving mid-send). The stream
    /// must recover instead of freezing on the last frame.
    func testDroppedUpdateRequestDoesNotFreezeTheScreen() async throws {
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
        server.answersEveryRequest = true
        server.requestsToDrop = 1
        server.start()
        let client = RFBClient()
        client.connect(request(port: server.port, username: "", password: "pw123456"))

        do {
            try await waitUntil(timeout: 4) { server.framesSent >= 4 }
        } catch {
            XCTFail("screen froze after a dropped request: only \(server.framesSent) frames sent")
            return
        }
        client.disconnect()
    }

    /// A Mac that ignores the first request for its screen must still
    /// show up, instead of leaving "Waiting for the Mac's screen" forever.
    func testIgnoredFirstScreenRequestIsAskedAgain() async throws {
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
        server.requestsToIgnoreBeforeScreen = 1
        server.start()
        let client = RFBClient()
        client.connect(request(port: server.port, username: "", password: "pw123456"))
        do {
            try await waitUntil(timeout: 4) { client.hasScreen }
        } catch {
            XCTFail("screen never arrived after an ignored request; state = \(client.state)")
            return
        }
        client.disconnect()
    }

    /// A Mac that logs in but never sends its screen gets one fresh
    /// session, then a clear explanation — never an endless spinner.
    func testMacThatNeverSendsItsScreenFailsClearly() async throws {
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
        server.requestsToIgnoreBeforeScreen = .max
        server.start()
        let client = RFBClient()
        client.connect(request(port: server.port, username: "", password: "pw123456"))
        do {
            try await waitUntil(timeout: 30) {
                if case .failed = client.state { return true }
                return false
            }
        } catch {
            XCTFail("expected a failure; state = \(client.state)")
            return
        }
        XCTAssertEqual(server.connections, 2, "should reconnect once before giving up")
        guard case .failed(let message) = client.state else { return }
        XCTAssertTrue(message.contains("Screen Sharing off and on"), message)
    }

    func testHextileAndZlibScreensDecodeExactly() async throws {
        for encoding in [RFBEncoding.hextile, RFBEncoding.zlib, RFBEncoding.zrle] {
            let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
            server.screenEncoding = encoding
            server.start()
            let client = RFBClient()
            client.connect(request(port: server.port, username: "", password: "pw123456"))
            do {
                try await waitUntil { client.hasScreen }
            } catch {
                XCTFail("encoding \(encoding): never received the screen; state = \(client.state)")
                continue
            }
            let screen = try XCTUnwrap(client.snapshot())
            for (index, expected) in screenPixels.enumerated() {
                XCTAssertEqual(rgb(screen, x: index % 3, y: index / 3), expected, "encoding \(encoding) pixel \(index)")
            }
            XCTAssertTrue(server.requestedEncodings.contains(encoding))
            client.disconnect()
        }
    }

    /// The old per-field actor hops made a single Retina Hextile frame take
    /// hundreds of milliseconds even over loopback, before drawing started.
    func testRetinaHextileScreenArrivesWithoutDecoderBacklog() async throws {
        let width = 3024, height = 1964
        var update = Data([0, 0, 0, 1])
        for value in [0, 0, width, height] { update.appendBE(UInt16(value)) }
        update.appendBE(RFBEncoding.hextile)
        for y in stride(from: 0, to: height, by: 16) {
            for x in stride(from: 0, to: width, by: 16) {
                if (x / 16 + y / 16) % 5 == 0 {
                    update.append(1) // raw photo tile
                    update.append(Data(repeating: 0x7f, count: min(16, width - x) * min(16, height - y) * 4))
                } else {
                    update.append(contentsOf: [2, 0x33, 0x22, 0x11, 0]) // solid desktop tile
                }
            }
        }
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: width, height: height,
                                       pixels: [UInt32](repeating: 0, count: width * height))
        server.screenUpdateOverride = update
        server.start()
        let client = RFBClient()
        defer { client.disconnect() }
        client.connect(request(port: server.port, username: "", password: "pw123456"))
        try await waitUntil { client.hasScreen }
        let elapsed = Date().timeIntervalSince(try XCTUnwrap(server.screenStartedAt))
        print("Retina Hextile receive + decode: \(elapsed)s")
        XCTAssertLessThan(elapsed, 0.25, "one frame must not build a screen-update backlog")
        let screen = try XCTUnwrap(client.snapshot())
        XCTAssertEqual(rgb(screen, x: 0, y: 0), 0x7f7f7f)
        XCTAssertEqual(rgb(screen, x: 16, y: 0), 0x112233)
        XCTAssertEqual(rgb(screen, x: width - 1, y: height - 1), 0x7f7f7f)
    }

    func testFragmentedHextileCarriesColoursAndPreservesFollowingMessages() async throws {
        // Six tiles, including partial right/bottom edges, raw pixels and
        // both subrectangle modes. Send byte by byte and in larger chunks.
        for chunkSize in [1, 7, 4096] {
            let width = 35, height = 18
            var update = Data([0, 0, 0, 1])
            for value in [0, 0, width, height] { update.appendBE(UInt16(value)) }
            update.appendBE(RFBEncoding.hextile)
            update.append(contentsOf: [14, 0x33, 0x22, 0x11, 0, 0x66, 0x55, 0x44, 0, 1, 0x12, 0x23])
            update.append(contentsOf: [8, 1, 0x00, 0x00]) // carry both colours into tile 2
            update.append(contentsOf: [24, 1, 0x99, 0x88, 0x77, 0, 0x20, 0x01]) // coloured edge tile
            update.append(1)
            update.append(Data(repeating: 0xaa, count: 16 * 2 * 4)) // raw tile invalidates carried colours
            update.append(contentsOf: [6, 0x33, 0x22, 0x11, 0, 0x66, 0x55, 0x44, 0]) // fresh background/foreground
            update.append(contentsOf: [8, 1, 0x00, 0x11]) // carried foreground at bottom right
            // A second update in the same TCP buffer catches over-reading.
            update.append(contentsOf: [0, 0, 0, 1])
            for value in [34, 17, 1, 1] { update.appendBE(UInt16(value)) }
            update.appendBE(RFBEncoding.raw)
            update.append(contentsOf: [0xef, 0xcd, 0xab, 0])

            let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: width, height: height,
                                           pixels: [UInt32](repeating: 0, count: width * height))
            server.screenUpdateOverride = update
            server.screenChunkSize = chunkSize
            server.screenChunkDelay = chunkSize == 1 ? 100 : 0
            server.start()
            let client = RFBClient()
            defer { client.disconnect() }
            client.connect(request(port: server.port, username: "", password: "pw123456"))
            try await waitUntil { server.updateRequests >= 3 }
            let screen = try XCTUnwrap(client.snapshot())
            XCTAssertEqual(rgb(screen, x: 0, y: 0), 0x112233)
            XCTAssertEqual(rgb(screen, x: 1, y: 2), 0x445566)
            XCTAssertEqual(rgb(screen, x: 16, y: 0), 0x445566)
            XCTAssertEqual(rgb(screen, x: 34, y: 1), 0x778899)
            XCTAssertEqual(rgb(screen, x: 0, y: 17), 0xaaaaaa)
            XCTAssertEqual(rgb(screen, x: 16, y: 17), 0x112233)
            XCTAssertEqual(rgb(screen, x: 33, y: 17), 0x445566)
            XCTAssertEqual(rgb(screen, x: 34, y: 17), 0xabcdef)
        }
    }

    func testMalformedHextileSubrectangleFailsTheSession() async throws {
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
        var update = Data([0, 0, 0, 1])
        for value in [0, 0, 3, 2] { update.appendBE(UInt16(value)) }
        update.appendBE(RFBEncoding.hextile)
        update.append(contentsOf: [8, 1, 0x21, 0x11]) // 2×2 at (2,1), outside a 3×2 tile
        server.screenUpdateOverride = update
        server.start()
        let client = RFBClient()
        defer { client.disconnect() }
        client.connect(request(port: server.port, username: "", password: "pw123456"))
        try await waitUntil {
            if case .failed = client.state { return true }
            return false
        }
        guard case .failed(let message) = client.state else { return XCTFail("expected malformed data to fail") }
        XCTAssertTrue(message.contains("hextile subrect outside its tile"), message)
    }

    func testNextRequestWaitsForTheEntireFinalCompressedPayload() async throws {
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
        let chunks = zlibCompressInTwoFlushes([0, 0, 0, 255, 0, 255, 0, 255, 0, 0],
                                            [0, 255, 255, 255, 0, 0, 0, 128, 128, 128])
        var update = Data([0, 0, 0, 2])
        for (y, compressed) in [chunks.0, chunks.1].enumerated() {
            for value in [0, y, 3, 1] { update.appendBE(UInt16(value)) }
            update.appendBE(RFBEncoding.zrle)
            update.appendBE(UInt32(compressed.count))
            update.append(compressed)
        }
        server.screenUpdateOverride = update
        server.screenChunkSize = update.count - 2 // hold the last two payload bytes
        server.screenChunkDelay = 350_000
        server.probeNextRequestDuringFirstScreen = true
        server.start()
        let client = RFBClient()
        defer { client.disconnect() }
        client.setStreamMode(.efficient)
        client.connect(request(port: server.port, username: "", password: "pw123456"))
        try await waitUntil { client.hasScreen && server.nextRequestAt != nil }
        let sentAt = try XCTUnwrap(server.screenStartedAt)
        let requestedAt = try XCTUnwrap(server.nextRequestAt)
        XCTAssertGreaterThan(requestedAt.timeIntervalSince(sentAt), 0.33,
                             "a request sent before the final payload can be dropped by macOS")
        let screen = try XCTUnwrap(client.snapshot())
        for (index, expected) in screenPixels.enumerated() {
            XCTAssertEqual(rgb(screen, x: index % 3, y: index / 3), expected)
        }
    }

    func testStreamModeCanChangeWithoutReconnecting() async throws {
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
        server.answersEveryRequest = true
        server.start()
        let client = RFBClient()
        defer { client.disconnect() }
        client.connect(request(port: server.port, username: "", password: "pw123456"))
        try await waitUntil { client.hasScreen }
        XCTAssertEqual(server.requestedEncodings, RFBStreamMode.responsive.encodings)
        client.setStreamMode(.efficient)
        try await waitUntil { server.requestedEncodings == RFBStreamMode.efficient.encodings }
        let frames = server.framesSent
        try await waitUntil { server.framesSent > frames }
        XCTAssertEqual(server.connections, 1)
        XCTAssertEqual(client.state, .connected)
    }

    func testInputPacerCoalescesMotionWithoutDroppingButtonsOrKeys() async throws {
        var sent: [Data] = []
        let pacer = RFBInputPacer { sent.append($0) }
        for x in 0..<1000 {
            pacer.enqueue(RFBClientMessage.pointerEvent(buttons: [], x: UInt16(x), y: 0), motion: true)
        }
        XCTAssertTrue(sent.isEmpty)
        let press = RFBClientMessage.pointerEvent(buttons: .left, x: 999, y: 0)
        pacer.enqueue(press)
        for x in 1000..<2000 {
            pacer.enqueue(RFBClientMessage.pointerEvent(buttons: .left, x: UInt16(x), y: 0), motion: true)
        }
        let release = RFBClientMessage.pointerEvent(buttons: [], x: 1999, y: 0)
        pacer.enqueue(release)
        let keyDown = RFBClientMessage.keyEvent(keysym: 0x61, down: true)
        let keyUp = RFBClientMessage.keyEvent(keysym: 0x61, down: false)
        pacer.enqueue(keyDown)
        pacer.enqueue(keyUp)
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(sent, [
            RFBClientMessage.pointerEvent(buttons: [], x: 999, y: 0), press,
            RFBClientMessage.pointerEvent(buttons: .left, x: 1999, y: 0), release, keyDown, keyUp,
        ])
        pacer.enqueue(RFBClientMessage.pointerEvent(buttons: [], x: 2000, y: 0), motion: true)
        try await waitUntil { sent.count == 7 }
        XCTAssertEqual(sent.last, RFBClientMessage.pointerEvent(buttons: [], x: 2000, y: 0))
        pacer.enqueue(RFBClientMessage.pointerEvent(buttons: [], x: 3000, y: 0), motion: true)
        pacer.cancel()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(sent.count, 7, "disconnect must discard unsent movement")
    }

    func testVNCPasswordLoginIsUsedWhenNoUsernameIsGiven() async throws {
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
        server.start()
        let client = RFBClient()
        client.connect(request(port: server.port, username: "", password: "pw123456"))

        do {
            try await waitUntil { client.hasScreen }
        } catch {
            XCTFail("never received the screen; state = \(client.state)")
            return
        }
        XCTAssertEqual(client.state, .connected)
        client.disconnect()
    }

    func testWrongPasswordReportsTheMacsReason() async throws {
        let server = try FakeRFBServer(login: .macAccount(username: "zaki", password: "right"), width: 3, height: 2, pixels: screenPixels)
        server.start()
        let client = RFBClient()
        client.connect(request(port: server.port, username: "zaki", password: "wrong"))

        do {
            try await waitUntil {
                if case .failed = client.state { return true }
                return false
            }
        } catch {
            XCTFail("expected a failure; state = \(client.state)")
            return
        }
        guard case .failed(let message) = client.state else { return XCTFail("expected failure") }
        XCTAssertTrue(message.hasPrefix("Authentication failed."), message)
        XCTAssertTrue(message.contains("Screen Sharing"), message)
        XCTAssertFalse(client.hasScreen)
    }

    /// A route that never answers (like Bonjour resolving onto an interface
    /// that doesn't route) must not hang: the next route is tried.
    func testHungRouteFallsThroughToTheNextOne() async throws {
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
        server.start()
        var reached: (String, UInt16)?
        let client = RFBClient()
        client.connect(MacConnectionRequest(
            endpoint: .hostPort(host: "10.255.255.1", port: 5900), // unroutable: never answers
            fallbacks: [.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: server.port)!)],
            displayName: "Test",
            username: "",
            password: "pw123456",
            onReachedAddress: { host, port in reached = (host, port) }
        ))

        do {
            try await waitUntil(timeout: 15) { client.hasScreen }
        } catch {
            XCTFail("never fell back to the working route; state = \(client.state)")
            return
        }
        XCTAssertEqual(reached?.0, "127.0.0.1")
        XCTAssertEqual(reached?.1, server.port)
        client.disconnect()
    }

    func testUnreachableMacFailsWithAHelpfulMessage() async throws {
        let client = RFBClient()
        client.connect(request(port: 1, username: "zaki", password: "x"))
        do {
            try await waitUntil(timeout: 12) {
                if case .failed = client.state { return true }
                return false
            }
        } catch {
            XCTFail("expected a failure; state = \(client.state)")
            return
        }
        guard case .failed(let message) = client.state else { return }
        XCTAssertTrue(message.contains("Screen Sharing"), message)
    }
}
