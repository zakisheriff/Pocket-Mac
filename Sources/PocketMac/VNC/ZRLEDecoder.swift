import Foundation
import zlib

/// Decodes ZRLE rectangles (RFC 6143 §7.7.6): one zlib stream that lives for
/// the whole connection, carrying 64×64 tiles that are raw, solid, palette
/// packed or run-length encoded.
///
/// Assumes the session's pixel format is `RFBPixelFormat.bgrx`, so every
/// compressed pixel ("CPIXEL") is 3 bytes: blue, green, red.
final class ZRLEDecoder {
    private var stream = z_stream()
    private var isInitialized = false
    /// Reused between rectangles so a busy screen doesn't allocate per frame.
    private var inflated = [UInt8]()

    deinit {
        if isInitialized { inflateEnd(&stream) }
    }

    @_optimize(speed)
    func decode(x: Int, y: Int, width: Int, height: Int, compressed: Data, into framebuffer: RFBFramebuffer) throws {
        guard framebuffer.contains(x: x, y: y, width: width, height: height) else {
            throw RFBError.protocolViolation("ZRLE rect is outside the screen")
        }
        let length = try inflate(compressed)

        try inflated.withUnsafeBufferPointer { buffer in
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
            for row in 0..<height {
                let line = origin + row * stride
                for column in 0..<width { line[column] = try reader.cpixel() }
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

    /// Inflates into the reusable buffer and returns the number of bytes produced.
    @_optimize(speed)
    private func inflate(_ input: Data) throws -> Int {
        if !isInitialized {
            let status = inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
            guard status == Z_OK else { throw RFBError.protocolViolation("zlib init failed (\(status))") }
            isInitialized = true
        }
        if inflated.count < max(input.count * 4, 64 * 1024) {
            inflated = [UInt8](repeating: 0, count: max(input.count * 4, 64 * 1024))
        }

        var produced = 0
        try input.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            while true {
                if produced == inflated.count {
                    inflated.append(contentsOf: [UInt8](repeating: 0, count: inflated.count))
                }
                let space = inflated.count - produced
                let status: Int32 = inflated.withUnsafeMutableBufferPointer { destination in
                    stream.next_out = destination.baseAddress! + produced
                    stream.avail_out = uInt(space)
                    return zlib.inflate(&stream, Z_SYNC_FLUSH)
                }
                guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                    throw RFBError.protocolViolation("zlib inflate failed (\(status))")
                }
                let wrote = space - Int(stream.avail_out)
                produced += wrote
                if stream.avail_in == 0 && stream.avail_out > 0 { break }
                if wrote == 0 && status == Z_BUF_ERROR { break }
            }
            stream.next_in = nil
        }
        return produced
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
