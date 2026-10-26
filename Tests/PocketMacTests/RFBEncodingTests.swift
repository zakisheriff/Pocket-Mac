import XCTest
import zlib
@testable import Pocket_Mac

final class RFBMessagesTests: XCTestCase {

    func testPointerEventLayout() {
        let data = RFBClientMessage.pointerEvent(buttons: [.left, .right], x: 0x0102, y: 0x0304)
        XCTAssertEqual([UInt8](data), [5, 0b101, 0x01, 0x02, 0x03, 0x04])
    }

    func testKeyEventLayout() {
        let data = RFBClientMessage.keyEvent(keysym: Keysym.returnKey, down: true)
        XCTAssertEqual([UInt8](data), [4, 1, 0, 0, 0x00, 0x00, 0xff, 0x0d])
    }

    func testSetEncodingsEncodesNegativePseudoEncodings() {
        let data = RFBClientMessage.setEncodings([RFBEncoding.zrle, RFBEncoding.cursor])
        XCTAssertEqual([UInt8](data), [2, 0, 0, 2, 0, 0, 0, 16, 0xff, 0xff, 0xff, 0x11])
    }

    func testPixelFormatRoundTrips() {
        let encoded = RFBPixelFormat.bgrx.encoded
        XCTAssertEqual(encoded.count, 16)
        XCTAssertEqual(RFBPixelFormat(data: encoded), .bgrx)
    }

    func testUpdateRequestLayout() {
        let data = RFBClientMessage.framebufferUpdateRequest(incremental: true, x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual([UInt8](data), [3, 1, 0, 0, 0, 0, 0x05, 0xe8, 0x03, 0xd6])
    }
}

final class KeysymTests: XCTestCase {

    func testPrintableCharactersMapToTheirCodePoints() {
        XCTAssertEqual(Keysym.character("a"), 0x61)
        XCTAssertEqual(Keysym.character("A"), 0x41)
        XCTAssertEqual(Keysym.character(" "), 0x20)
        XCTAssertEqual(Keysym.character("é"), 0xe9)
    }

    func testControlCharactersMapToSpecialKeys() {
        XCTAssertEqual(Keysym.character("\n"), Keysym.returnKey)
        XCTAssertEqual(Keysym.character("\t"), Keysym.tab)
    }

    func testNonLatinCharactersUseUnicodeKeysyms() {
        XCTAssertEqual(Keysym.character("€"), 0x0100_20ac)
    }

    func testFunctionKeys() {
        XCTAssertEqual(Keysym.function(1), 0xffbe)
        XCTAssertEqual(Keysym.function(12), 0xffc9)
    }
}

final class RFBFramebufferTests: XCTestCase {

    private func pixel(_ framebuffer: RFBFramebuffer, _ x: Int, _ y: Int) -> UInt32 {
        framebuffer.withPixelWords { words, stride in words[y * stride + x] & 0x00FF_FFFF }
    }

    func testRawBlitPlacesPixels() throws {
        let framebuffer = RFBFramebuffer(width: 4, height: 4)
        var data = Data()
        for value: UInt32 in [0x111111, 0x222222, 0x333333, 0x444444] {
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init))
        }
        try framebuffer.blitRaw(x: 1, y: 2, width: 2, height: 2, data: data)
        XCTAssertEqual(pixel(framebuffer, 1, 2), 0x111111)
        XCTAssertEqual(pixel(framebuffer, 2, 3), 0x444444)
        XCTAssertEqual(pixel(framebuffer, 0, 0), 0)
    }

    func testRawBlitOutsideTheScreenIsRejected() {
        let framebuffer = RFBFramebuffer(width: 4, height: 4)
        XCTAssertThrowsError(try framebuffer.blitRaw(x: 3, y: 3, width: 2, height: 2, data: Data(count: 16)))
    }

    func testOverlappingCopyRectDownwardsKeepsSourceRows() throws {
        let framebuffer = RFBFramebuffer(width: 1, height: 4)
        for row in 0..<4 { framebuffer.fill(x: 0, y: row, width: 1, height: 1, pixel: UInt32(row + 1)) }
        try framebuffer.copyRect(fromX: 0, fromY: 0, toX: 0, toY: 1, width: 1, height: 3)
        XCTAssertEqual((0..<4).map { pixel(framebuffer, 0, $0) }, [1, 1, 2, 3])
    }

    func testImageHasTheScreenSize() {
        let image = RFBFramebuffer(width: 12, height: 7).makeImage()
        XCTAssertEqual(image?.width, 12)
        XCTAssertEqual(image?.height, 7)
    }
}

final class ZRLEDecoderTests: XCTestCase {

    private func pixel(_ framebuffer: RFBFramebuffer, _ x: Int, _ y: Int) -> UInt32 {
        framebuffer.withPixelWords { words, stride in words[y * stride + x] & 0x00FF_FFFF }
    }

    private func cpixel(_ rgb: UInt32) -> [UInt8] {
        [UInt8(rgb & 0xff), UInt8((rgb >> 8) & 0xff), UInt8((rgb >> 16) & 0xff)]
    }

    func testSolidRawAndPaletteRLETiles() throws {
        // A 70×2 rect is two tiles: 64×2 then 6×2.
        var tiles: [UInt8] = []
        tiles += [1] + cpixel(0xff0000)                       // tile 1: solid red
        tiles += [130] + cpixel(0x00ff00) + cpixel(0x0000ff)   // tile 2: 2-colour palette RLE
        tiles += [0x80, 5]                                     // palette[0] green, run 5+1 = 6 (row 0)
        tiles += [0x81, 5]                                     // palette[1] blue, run 6 (row 1)

        let framebuffer = RFBFramebuffer(width: 70, height: 2)
        try ZRLEDecoder().decode(x: 0, y: 0, width: 70, height: 2, compressed: zlibCompress(tiles), into: framebuffer)

        XCTAssertEqual(pixel(framebuffer, 0, 0), 0xff0000)
        XCTAssertEqual(pixel(framebuffer, 63, 1), 0xff0000)
        XCTAssertEqual(pixel(framebuffer, 64, 0), 0x00ff00)
        XCTAssertEqual(pixel(framebuffer, 69, 0), 0x00ff00)
        XCTAssertEqual(pixel(framebuffer, 64, 1), 0x0000ff)
        XCTAssertEqual(pixel(framebuffer, 69, 1), 0x0000ff)
    }

    func testPackedPaletteTileWithOneBitIndices() throws {
        // 4×1 tile, palette [black, white], indices 0 1 1 0 → 0b0110_0000.
        let tile: [UInt8] = [2] + cpixel(0x000000) + cpixel(0xffffff) + [0b0110_0000]
        let framebuffer = RFBFramebuffer(width: 4, height: 1)
        try ZRLEDecoder().decode(x: 0, y: 0, width: 4, height: 1, compressed: zlibCompress(tile), into: framebuffer)
        XCTAssertEqual((0..<4).map { pixel(framebuffer, $0, 0) }, [0, 0xffffff, 0xffffff, 0])
    }

    func testStreamStateCarriesAcrossRectangles() throws {
        // macOS keeps one zlib stream for the whole session; split one
        // deflate stream across two rects and decode both in order.
        let first: [UInt8] = [1] + cpixel(0x123456)
        let second: [UInt8] = [1] + cpixel(0x654321)
        let (chunkA, chunkB) = zlibCompressInTwoFlushes(first, second)

        let decoder = ZRLEDecoder()
        let framebuffer = RFBFramebuffer(width: 2, height: 1)
        try decoder.decode(x: 0, y: 0, width: 1, height: 1, compressed: chunkA, into: framebuffer)
        try decoder.decode(x: 1, y: 0, width: 1, height: 1, compressed: chunkB, into: framebuffer)
        XCTAssertEqual(pixel(framebuffer, 0, 0), 0x123456)
        XCTAssertEqual(pixel(framebuffer, 1, 0), 0x654321)
    }

    func testCorruptSubencodingThrows() {
        let framebuffer = RFBFramebuffer(width: 1, height: 1)
        XCTAssertThrowsError(try ZRLEDecoder().decode(x: 0, y: 0, width: 1, height: 1, compressed: zlibCompress([50]), into: framebuffer))
    }
}

func zlibCompress(_ bytes: [UInt8]) -> Data {
    zlibCompressInTwoFlushes(bytes, []).0
}

/// Deflates `first`, sync-flushes, then deflates `second` on the same
/// stream, returning each flushed chunk — exactly what a VNC server sends.
func zlibCompressInTwoFlushes(_ first: [UInt8], _ second: [UInt8]) -> (Data, Data) {
    var stream = z_stream()
    deflateInit_(&stream, Z_DEFAULT_COMPRESSION, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
    defer { deflateEnd(&stream) }

    func flush(_ input: [UInt8]) -> Data {
        var input = input
        // Incompressible data deflates slightly larger than it started.
        var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(input.count))) + 1024)
        input.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                stream.next_in = inBuffer.baseAddress
                stream.avail_in = uInt(inBuffer.count)
                stream.next_out = outBuffer.baseAddress
                stream.avail_out = uInt(outBuffer.count)
                deflate(&stream, Z_SYNC_FLUSH)
            }
        }
        return Data(output[0..<(output.count - Int(stream.avail_out))])
    }
    return (flush(first), flush(second))
}
