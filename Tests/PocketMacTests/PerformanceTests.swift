import XCTest
import Metal
import QuartzCore
@testable import Pocket_Mac

/// Budgets for a full Retina MacBook screen (3024×1964). The decoder runs
/// for every frame the Mac sends, so these bound how fast the phone keeps up.
final class PerformanceTests: XCTestCase {
    private let width = 3024
    private let height = 1964

    private func time(_ body: () throws -> Void) rethrows -> TimeInterval {
        let start = Date()
        try body()
        return Date().timeIntervalSince(start)
    }

    func testFullScreenRawUpdateIsFast() throws {
        let framebuffer = RFBFramebuffer(width: width, height: height)
        let pixels = Data(repeating: 0x7f, count: width * height * 4)
        _ = try time { try framebuffer.blitRaw(x: 0, y: 0, width: width, height: height, data: pixels) } // warm up
        let elapsed = try time { try framebuffer.blitRaw(x: 0, y: 0, width: width, height: height, data: pixels) }
        XCTAssertLessThan(elapsed, 0.05, "raw full-screen blit took \(elapsed)s")
    }

    /// A realistic desktop frame: mostly flat tiles, some palette text, some photo.
    func testFullScreenDesktopZRLEFrameIsFast() throws {
        let frame = makeZRLEFrame { index in
            switch index % 10 {
            case 0: return .raw
            case 1, 2: return .paletteRLE
            default: return .solid
            }
        }
        let framebuffer = RFBFramebuffer(width: width, height: height)
        let decoder = ZRLEDecoder()
        let elapsed = try time {
            try decoder.decode(x: 0, y: 0, width: width, height: height, compressed: frame, into: framebuffer)
        }
        XCTAssertLessThan(elapsed, 0.1, "desktop ZRLE frame took \(elapsed)s")
    }

    /// Worst case: every tile is raw (a full-screen photo or video).
    func testFullScreenWorstCaseZRLEFrameStaysUsable() throws {
        let frame = makeZRLEFrame { _ in .raw }
        let framebuffer = RFBFramebuffer(width: width, height: height)
        let elapsed = try time {
            try ZRLEDecoder().decode(x: 0, y: 0, width: width, height: height, compressed: frame, into: framebuffer)
        }
        XCTAssertLessThan(elapsed, 0.4, "all-raw ZRLE frame took \(elapsed)s")
    }

    func testLiveImageIsCreatedWithoutCopying() {
        let framebuffer = RFBFramebuffer(width: width, height: height)
        _ = framebuffer.makeLiveImage()
        let elapsed = time { for _ in 0..<100 { _ = framebuffer.makeLiveImage() } }
        XCTAssertLessThan(elapsed / 100, 0.001, "making a frame image took \(elapsed / 100)s")
    }

    /// Exhaust the drawable pool deliberately. Rendering used to wait up to
    /// a second here on the same thread that handles trackpad input.
    @MainActor
    func testDrawableBackpressureDoesNotBlockInput() async throws {
        let renderer = try XCTUnwrap(MetalScreenRenderer())
        let framebuffer = RFBFramebuffer(width: 64, height: 64)
        XCTAssertTrue(renderer.setSurface(framebuffer.surface, width: 64, height: 64))
        renderer.layer.maximumDrawableCount = 2
        var heldDrawables: [CAMetalDrawable] = [
            try XCTUnwrap(renderer.layer.nextDrawable()),
            try XCTUnwrap(renderer.layer.nextDrawable()),
        ]
        let elapsed = time { XCTAssertTrue(renderer.draw(retry: {})) }
        XCTAssertLessThan(elapsed, 0.05, "GPU backpressure must not block touch handling")
        // The busy worker must reject another frame instead of queuing it.
        XCTAssertFalse(renderer.draw(retry: {}))
        let input = expectation(description: "main thread handles input while GPU is blocked")
        DispatchQueue.main.async { input.fulfill() }
        await fulfillment(of: [input], timeout: 0.25)
        XCTAssertEqual(heldDrawables.count, 2)
        heldDrawables.removeAll()
    }

    // MARK: Frame builder

    private enum TileKind { case solid, paletteRLE, raw }

    private func makeZRLEFrame(kind: (Int) -> TileKind) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height)
        var tileIndex = 0
        var seed: UInt32 = 12345
        func next() -> UInt8 {
            seed = seed &* 1_103_515_245 &+ 12345
            return UInt8(truncatingIfNeeded: seed >> 16)
        }

        for tileY in stride(from: 0, to: height, by: 64) {
            for tileX in stride(from: 0, to: width, by: 64) {
                let tileWidth = min(64, width - tileX)
                let tileHeight = min(64, height - tileY)
                let pixels = tileWidth * tileHeight
                switch kind(tileIndex) {
                case .solid:
                    bytes += [1, 0xee, 0xee, 0xee]
                case .paletteRLE:
                    bytes += [130, 0xff, 0xff, 0xff, 0x20, 0x20, 0x20]
                    var remaining = pixels
                    while remaining > 0 {
                        let run = min(remaining, Int(next() % 12) + 1)
                        bytes += [0x80 | (next() & 1), UInt8(run - 1)]
                        remaining -= run
                    }
                case .raw:
                    bytes.append(0)
                    for _ in 0..<(pixels * 3) { bytes.append(next()) }
                }
                tileIndex += 1
            }
        }
        return zlibCompress(bytes)
    }
}
