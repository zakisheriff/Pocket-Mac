import Foundation

/// Hextile encoding (RFC 6143 §7.7.4, type 5): the rectangle is split into
/// 16×16 tiles, each raw or a background colour plus small subrectangles.
/// Background and foreground colours carry over from tile to tile.
enum HextileDecoder {
    private static let raw: UInt8 = 1
    private static let backgroundSpecified: UInt8 = 2
    private static let foregroundSpecified: UInt8 = 4
    private static let anySubrects: UInt8 = 8
    private static let subrectsColoured: UInt8 = 16

    static func decode(
        x: Int, y: Int, width: Int, height: Int,
        from stream: RFBStream, into framebuffer: RFBFramebuffer
    ) async throws {
        guard framebuffer.contains(x: x, y: y, width: width, height: height) else {
            throw RFBError.protocolViolation("hextile rect is outside the screen")
        }
        var background: UInt32 = 0
        var foreground: UInt32 = 0

        var tileY = y
        while tileY < y + height {
            let tileHeight = min(16, y + height - tileY)
            var tileX = x
            while tileX < x + width {
                let tileWidth = min(16, x + width - tileX)
                let flags = try await stream.readU8()

                if flags & raw != 0 {
                    let pixels = try await stream.read(tileWidth * tileHeight * 4)
                    try framebuffer.blitRaw(x: tileX, y: tileY, width: tileWidth, height: tileHeight, data: pixels)
                } else {
                    if flags & backgroundSpecified != 0 { background = pixel(try await stream.read(4)) }
                    if flags & foregroundSpecified != 0 { foreground = pixel(try await stream.read(4)) }
                    framebuffer.fill(x: tileX, y: tileY, width: tileWidth, height: tileHeight, pixel: background)

                    if flags & anySubrects != 0 {
                        let count = Int(try await stream.readU8())
                        let coloured = flags & subrectsColoured != 0
                        let entrySize = coloured ? 6 : 2
                        let entries = try await stream.read(count * entrySize)
                        for index in 0..<count {
                            var offset = entries.startIndex + index * entrySize
                            var colour = foreground
                            if coloured {
                                colour = pixel(entries[offset..<(offset + 4)])
                                offset += 4
                            }
                            let position = entries[offset]
                            let size = entries[offset + 1]
                            let subX = Int(position >> 4), subY = Int(position & 0x0f)
                            let subWidth = Int(size >> 4) + 1, subHeight = Int(size & 0x0f) + 1
                            guard subX + subWidth <= tileWidth, subY + subHeight <= tileHeight else {
                                throw RFBError.protocolViolation("hextile subrect outside its tile")
                            }
                            framebuffer.fill(x: tileX + subX, y: tileY + subY, width: subWidth, height: subHeight, pixel: colour)
                        }
                    }
                }
                tileX += 16
            }
            tileY += 16
        }
    }

    private static func pixel(_ bytes: Data) -> UInt32 {
        let i = bytes.startIndex
        return UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16
    }
}
