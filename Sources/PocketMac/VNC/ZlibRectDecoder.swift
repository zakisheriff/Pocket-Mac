import Foundation

/// Zlib encoding (RFC 6143 §7.7.3-style, type 6): raw pixels compressed with
/// a zlib stream that persists across rectangles.
final class ZlibRectDecoder {
    private let zlib = ZlibStream()

    func decode(x: Int, y: Int, width: Int, height: Int, compressed: Data, into framebuffer: RFBFramebuffer) throws {
        let length = try zlib.inflate(compressed)
        guard length >= width * height * 4 else {
            throw RFBError.protocolViolation("zlib rect is missing pixel data")
        }
        let pixels = zlib.withOutput { Data(buffer: UnsafeBufferPointer(rebasing: $0[0..<(width * height * 4)])) }
        try framebuffer.blitRaw(x: x, y: y, width: width, height: height, data: pixels)
    }
}
