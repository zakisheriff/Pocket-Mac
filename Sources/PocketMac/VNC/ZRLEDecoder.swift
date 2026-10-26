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

    deinit {
        if isInitialized { inflateEnd(&stream) }
    }

    func decode(x: Int, y: Int, width: Int, height: Int, compressed: Data, into framebuffer: RFBFramebuffer) throws {
        guard framebuffer.contains(x: x, y: y, width: width, height: height) else {
            throw RFBError.protocolViolation("ZRLE rect is outside the screen")
        }
        let data = try inflate(compressed)
        var reader = ByteReader(data: data)

        try framebuffer.withPixelWords { pixels, stride in
            var tileY = 0
            while tileY < height {
                let tileHeight = min(64, height - tileY)
                var tileX = 0
                while tileX < width {
                    let tileWidth = min(64, width - tileX)
                    try decodeTile(
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

    private func decodeTile(_ reader: inout ByteReader, origin: UnsafeMutablePointer<UInt32>, stride: Int, width: Int, height: Int) throws {
        let subencoding = try reader.u8()
        let total = width * height

        func put(_ index: Int, _ pixel: UInt32) {
            origin[(index / width) * stride + index % width] = pixel.littleEndian
        }

        switch subencoding {
        case 0:
            for index in 0..<total { put(index, try reader.cpixel()) }

        case 1:
            let pixel = try reader.cpixel()
            for row in 0..<height {
                (origin + row * stride).update(repeating: pixel.littleEndian, count: width)
            }

        case 2...16:
            let palette = try (0..<Int(subencoding)).map { _ in try reader.cpixel() }
            let bits = subencoding == 2 ? 1 : (subencoding <= 4 ? 2 : 4)
            let mask = UInt8((1 << bits) - 1)
            for row in 0..<height {
                var byte: UInt8 = 0
                var bitsLeft = 0
                for column in 0..<width {
                    if bitsLeft == 0 {
                        byte = try reader.u8()
                        bitsLeft = 8
                    }
                    bitsLeft -= bits
                    let paletteIndex = Int((byte >> UInt8(bitsLeft)) & mask)
                    guard paletteIndex < palette.count else {
                        throw RFBError.protocolViolation("ZRLE palette index out of range")
                    }
                    origin[row * stride + column] = palette[paletteIndex].littleEndian
                }
            }

        case 128:
            var index = 0
            while index < total {
                let pixel = try reader.cpixel()
                let run = try reader.runLength()
                guard index + run <= total else { throw RFBError.protocolViolation("ZRLE run overflows tile") }
                for offset in index..<(index + run) { put(offset, pixel) }
                index += run
            }

        case 130...255:
            let palette = try (0..<Int(subencoding - 128)).map { _ in try reader.cpixel() }
            var index = 0
            while index < total {
                let entry = try reader.u8()
                let paletteIndex = Int(entry & 0x7f)
                guard paletteIndex < palette.count else {
                    throw RFBError.protocolViolation("ZRLE palette index out of range")
                }
                let run = entry & 0x80 != 0 ? try reader.runLength() : 1
                guard index + run <= total else { throw RFBError.protocolViolation("ZRLE run overflows tile") }
                for offset in index..<(index + run) { put(offset, palette[paletteIndex]) }
                index += run
            }

        default:
            throw RFBError.protocolViolation("unknown ZRLE subencoding \(subencoding)")
        }
    }

    private func inflate(_ input: Data) throws -> Data {
        if !isInitialized {
            let status = inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
            guard status == Z_OK else { throw RFBError.protocolViolation("zlib init failed (\(status))") }
            isInitialized = true
        }

        var output = Data()
        var chunk = [UInt8](repeating: 0, count: 256 * 1024)
        try input.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            repeat {
                let produced: Int = try chunk.withUnsafeMutableBytes { destination in
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(destination.count)
                    let status = zlib.inflate(&stream, Z_SYNC_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else {
                        throw RFBError.protocolViolation("zlib inflate failed (\(status))")
                    }
                    return destination.count - Int(stream.avail_out)
                }
                output.append(contentsOf: chunk[0..<produced])
                if produced == 0 { break }
            } while stream.avail_in > 0 || stream.avail_out == 0
            stream.next_in = nil
        }
        return output
    }
}

private struct ByteReader {
    let data: Data
    var offset = 0

    mutating func u8() throws -> UInt8 {
        guard offset < data.count else { throw RFBError.protocolViolation("ZRLE data ended early") }
        defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    mutating func cpixel() throws -> UInt32 {
        guard offset + 3 <= data.count else { throw RFBError.protocolViolation("ZRLE data ended early") }
        let i = data.startIndex + offset
        offset += 3
        return UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16
    }

    /// Run lengths are a series of bytes summed until one is below 255, plus one.
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
