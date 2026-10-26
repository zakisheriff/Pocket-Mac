import Accelerate
import Foundation
import zlib

/// Decodes ZRLE rectangles (RFC 6143 §7.7.6): one zlib stream that lives for
/// the whole connection, carrying 64×64 tiles that are raw, solid, palette
/// packed or run-length encoded.
///
/// Assumes the session's pixel format is `RFBPixelFormat.bgrx`, so every
/// compressed pixel ("CPIXEL") is 3 bytes: blue, green, red.
final class ZRLEDecoder {
    private let zlib = ZlibStream()

    @_optimize(speed)
    func decode(x: Int, y: Int, width: Int, height: Int, compressed: Data, into framebuffer: RFBFramebuffer) throws {
        guard framebuffer.contains(x: x, y: y, width: width, height: height) else {
            throw RFBError.protocolViolation("ZRLE rect is outside the screen")
        }
        let length = try zlib.inflate(compressed)

        try zlib.withOutput { buffer in
            var reader = TileReader(base: buffer.baseAddress!, count: length)
            try framebuffer.withPixelWords { pixels, stride in
                var tileY = 0
                while tileY < height {
                    let tileHeight = min(64, height - tileY)
                    var tileX = 0
                    while tileX < width {
                        let tileWidth = min(64, width - tileX)
                        try Self.decodeTile(
                            &reader,
                            origin: pixels + (y + tileY) * stride + (x + tileX),
                            stride: stride,
                            width: tileWidth,
                            height: tileHeight
                        )
                        tileX += 64
                    }
                    tileY += 64
                }
            }
        }
    }

    @_optimize(speed)
    private static func decodeTile(_ reader: inout TileReader, origin: UnsafeMutablePointer<UInt32>, stride: Int, width: Int, height: Int) throws {
        let subencoding = try reader.u8()
        let total = width * height

        switch subencoding {
        case 0:
            let source = try reader.take(total * 3)
            var input = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: source),
                                      height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * 3)
            var output = vImage_Buffer(data: origin, height: vImagePixelCount(height),
                                       width: vImagePixelCount(width), rowBytes: stride * 4)
            // BGR → BGRA is the same byte expansion as RGB → RGBA. vImage
            // vectorises it; no throwing bounds check for each of 8M pixels.
            let status = vImageConvert_RGB888toRGBA8888(&input, nil, 255, &output, false, vImage_Flags(kvImageDoNotTile))
            guard status == kvImageNoError else {
                throw RFBError.protocolViolation("ZRLE pixel conversion failed (\(status))")
            }

        case 1:
            let pixel = try reader.cpixel()
            for row in 0..<height {
                (origin + row * stride).update(repeating: pixel, count: width)
            }

        case 2...16:
            var palette = (UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0),
                           UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0), UInt32(0))
            let size = Int(subencoding)
            try withUnsafeMutableBytes(of: &palette) { raw in
                let entries = raw.bindMemory(to: UInt32.self)
                for index in 0..<size { entries[index] = try reader.cpixel() }
                let bits = size == 2 ? 1 : (size <= 4 ? 2 : 4)
                let mask = UInt8((1 << bits) - 1)
                for row in 0..<height {
                    let line = origin + row * stride
                    var byte: UInt8 = 0
                    var bitsLeft = 0
                    for column in 0..<width {
                        if bitsLeft == 0 {
                            byte = try reader.u8()
                            bitsLeft = 8
                        }
                        bitsLeft -= bits
                        let index = Int((byte >> UInt8(bitsLeft)) & mask)
                        guard index < size else { throw RFBError.protocolViolation("ZRLE palette index out of range") }
                        line[column] = entries[index]
                    }
                }
            }

        case 128:
            var index = 0
            while index < total {
                let pixel = try reader.cpixel()
                let run = try reader.runLength()
                guard index + run <= total else { throw RFBError.protocolViolation("ZRLE run overflows tile") }
                fill(origin, stride: stride, width: width, from: index, count: run, pixel: pixel)
                index += run
            }

        case 130...255:
            var palette = [UInt32](repeating: 0, count: Int(subencoding - 128))
            for entry in 0..<palette.count { palette[entry] = try reader.cpixel() }
            var index = 0
            while index < total {
                let entry = try reader.u8()
                let paletteIndex = Int(entry & 0x7f)
                guard paletteIndex < palette.count else {
                    throw RFBError.protocolViolation("ZRLE palette index out of range")
                }
                let run = entry & 0x80 != 0 ? try reader.runLength() : 1
                guard index + run <= total else { throw RFBError.protocolViolation("ZRLE run overflows tile") }
                fill(origin, stride: stride, width: width, from: index, count: run, pixel: palette[paletteIndex])
                index += run
            }

        default:
            throw RFBError.protocolViolation("unknown ZRLE subencoding \(subencoding)")
        }
    }

    /// Writes a run that may wrap across tile rows.
    @_optimize(speed)
    private static func fill(_ origin: UnsafeMutablePointer<UInt32>, stride: Int, width: Int, from start: Int, count: Int, pixel: UInt32) {
        var remaining = count
        var row = start / width
        var column = start % width
        while remaining > 0 {
            let span = min(remaining, width - column)
            (origin + row * stride + column).update(repeating: pixel, count: span)
            remaining -= span
            row += 1
            column = 0
        }
    }
}

/// Bounds-checked reader over the inflated bytes, without Data overhead.
private struct TileReader {
    let base: UnsafePointer<UInt8>
    let count: Int
    var offset = 0

    @inline(__always)
    mutating func u8() throws -> UInt8 {
        guard offset < count else { throw RFBError.protocolViolation("ZRLE data ended early") }
        defer { offset += 1 }
        return base[offset]
    }

    @inline(__always)
    mutating func take(_ length: Int) throws -> UnsafePointer<UInt8> {
        guard length <= count - offset else { throw RFBError.protocolViolation("ZRLE data ended early") }
        defer { offset += length }
        return base + offset
    }

    /// 3-byte B,G,R → opaque BGRA word.
    @inline(__always)
    mutating func cpixel() throws -> UInt32 {
        guard offset + 3 <= count else { throw RFBError.protocolViolation("ZRLE data ended early") }
        let p = base + offset
        offset += 3
        return UInt32(p[0]) | UInt32(p[1]) << 8 | UInt32(p[2]) << 16 | RFBFramebuffer.opaque
    }

    /// Run lengths are a series of bytes summed until one is below 255, plus one.
    @inline(__always)
    mutating func runLength() throws -> Int {
        var length = 1
        var byte: UInt8
        repeat {
            byte = try u8()
            length += Int(byte)
        } while byte == 255
        return length
    }
}
