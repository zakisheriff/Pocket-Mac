import Foundation

/// Hextile (RFC 6143 §7.7.4): 16×16 tiles with colours carried between tiles.
/// Parses complete tiles directly from the socket buffer. A Retina screen
/// has over 23,000 tiles; allocating and awaiting every field adds seconds.
enum HextileDecoder {
    private static let raw: UInt8 = 1
    private static let backgroundSpecified: UInt8 = 2
    private static let foregroundSpecified: UInt8 = 4
    private static let anySubrects: UInt8 = 8
    private static let subrectsColoured: UInt8 = 16

    static func decode(
        x: Int, y: Int, width: Int, height: Int,
        from stream: isolated RFBStream, into framebuffer: RFBFramebuffer
    ) async throws {
        guard framebuffer.contains(x: x, y: y, width: width, height: height) else {
            throw RFBError.protocolViolation("hextile rect is outside the screen")
        }
        guard width > 0, height > 0 else { return }
        var rectangle = Rectangle(x: x, y: y, width: width, height: height)
        var needed = 1
        while !rectangle.finished {
            try Task.checkCancellation()
            try await stream.ensureBuffered(needed)
            needed = try stream.withBufferedBytes { bytes, consumed in
                try framebuffer.withPixelWords { pixels, stride in
                    try rectangle.decodeAvailable(bytes, consumed: &consumed, pixels: pixels, stride: stride)
                }
            }
        }
    }

    private struct Rectangle {
        let x: Int, y: Int, width: Int, height: Int
        private var tileX = 0
        private var tileY = 0
        private var background: UInt32 = 0
        private var foreground: UInt32 = 0

        init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var finished: Bool { tileY >= height }

        /// Returns the minimum bytes needed for the next incomplete tile.
        /// No parser state changes until a complete tile is available, so a
        /// packet can end anywhere, including inside a colour or subrectangle.
        mutating func decodeAvailable(
            _ bytes: UnsafeRawBufferPointer, consumed: inout Int,
            pixels: UnsafeMutablePointer<UInt32>, stride: Int
        ) throws -> Int {
            while !finished {
                let available = bytes.count - consumed
                guard available >= 1 else { return 1 }
                let tile = UnsafeRawBufferPointer(rebasing: bytes[consumed...])
                let flags = tile[0]
                let w = min(16, width - tileX), h = min(16, height - tileY)
                let origin = pixels + (y + tileY) * stride + x + tileX
                var length: Int

                if flags & raw != 0 {
                    length = 1 + w * h * 4
                    guard available >= length else { return length }
                    for row in 0..<h {
                        for column in 0..<w {
                            let value = tile.loadUnaligned(fromByteOffset: 1 + (row * w + column) * 4, as: UInt32.self)
                            origin[row * stride + column] = UInt32(littleEndian: value) | RFBFramebuffer.opaque
                        }
                    }
                } else {
                    guard flags & 0xe0 == 0 else {
                        throw RFBError.protocolViolation("invalid hextile flags")
                    }
                    let hasBackground = flags & backgroundSpecified != 0
                    let hasForeground = flags & foregroundSpecified != 0
                    let hasSubrects = flags & anySubrects != 0
                    let coloured = flags & subrectsColoured != 0
                    let headerSize = 1 + (hasBackground ? 4 : 0) + (hasForeground ? 4 : 0)
                    let minimum = headerSize + (hasSubrects ? 1 : 0)
                    guard available >= minimum else { return minimum }
                    let count = hasSubrects ? Int(tile[headerSize]) : 0
                    let entrySize = coloured ? 6 : 2
                    length = minimum + count * entrySize
                    guard available >= length else { return length }

                    var offset = 1
                    if hasBackground {
                        background = pixel(tile, at: offset)
                        offset += 4
                    }
                    if hasForeground { foreground = pixel(tile, at: offset) }
                    fill(origin, stride: stride, width: w, height: h, colour: background)
                    offset = minimum
                    for _ in 0..<count {
                        var colour = foreground
                        if coloured {
                            colour = pixel(tile, at: offset)
                            offset += 4
                        }
                        let position = tile[offset], size = tile[offset + 1]
                        offset += 2
                        let subX = Int(position >> 4), subY = Int(position & 0x0f)
                        let subWidth = Int(size >> 4) + 1, subHeight = Int(size & 0x0f) + 1
                        guard subX + subWidth <= w, subY + subHeight <= h else {
                            throw RFBError.protocolViolation("hextile subrect outside its tile")
                        }
                        fill(origin + subY * stride + subX, stride: stride,
                             width: subWidth, height: subHeight, colour: colour)
                    }
                }

                consumed += length
                tileX += 16
                if tileX >= width {
                    tileX = 0
                    tileY += 16
                }
            }
            return 0
        }

        private func pixel(_ bytes: UnsafeRawBufferPointer, at offset: Int) -> UInt32 {
            UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) | RFBFramebuffer.opaque
        }

        private func fill(_ origin: UnsafeMutablePointer<UInt32>, stride: Int, width: Int, height: Int, colour: UInt32) {
            for row in 0..<height {
                (origin + row * stride).update(repeating: colour | RFBFramebuffer.opaque, count: width)
            }
        }
    }
}
