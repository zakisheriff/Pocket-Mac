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
            if Date() > deadline { throw XCTSkip("condition not met in time") }
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
            try await waitUntil { client.screen != nil }
        } catch {
            XCTFail("never received the screen; state = \(client.state)")
            return
        }

        XCTAssertEqual(client.state, .connected)
        XCTAssertEqual(client.desktopName, "Fake Mac")
        XCTAssertEqual(client.screenSize, CGSize(width: 3, height: 2))
        let screen = try XCTUnwrap(client.screen)
        XCTAssertEqual(rgb(screen, x: 0, y: 0), 0xff0000)
        XCTAssertEqual(rgb(screen, x: 2, y: 1), 0x808080)

        XCTAssertTrue(server.requestedEncodings.contains(RFBEncoding.zrle))
        XCTAssertTrue(server.requestedEncodings.contains(RFBEncoding.cursor))

        client.movePointer(to: CGPoint(x: 2, y: 1))
        client.click()
        try await waitUntil { server.pointerEvents.count >= 3 }
        XCTAssertEqual(Array(server.pointerEvents.suffix(3)), [
            .init(buttons: 0, x: 2, y: 1),
            .init(buttons: 1, x: 2, y: 1),
            .init(buttons: 0, x: 2, y: 1),
        ])

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

    func testVNCPasswordLoginIsUsedWhenNoUsernameIsGiven() async throws {
        let server = try FakeRFBServer(login: .vncPassword("pw123456"), width: 3, height: 2, pixels: screenPixels)
        server.start()
        let client = RFBClient()
        client.connect(request(port: server.port, username: "", password: "pw123456"))

        do {
            try await waitUntil { client.screen != nil }
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
        XCTAssertEqual(client.state, .failed("Authentication failed"))
        XCTAssertNil(client.screen)
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
