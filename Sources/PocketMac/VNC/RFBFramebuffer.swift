import CoreGraphics
import Foundation

/// The client-side copy of the Mac's screen, stored as 32-bit BGRX pixels
/// (`RFBPixelFormat.bgrx`). Only touched from the session's receive loop.
final class RFBFramebuffer {
    private(set) var width: Int
    private(set) var height: Int
    private(set) var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    var bytesPerRow: Int { width * 4 }

    func resize(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    func contains(x: Int, y: Int, width w: Int, height h: Int) -> Bool {
        x >= 0 && y >= 0 && w >= 0 && h >= 0 && x + w <= width && y + h <= height
    }

    /// Copies a rectangle of tightly packed BGRX pixels into place.
    func blitRaw(x: Int, y: Int, width w: Int, height h: Int, data: Data) throws {
        guard contains(x: x, y: y, width: w, height: h) else {
            throw RFBError.protocolViolation("raw rect \(w)x\(h) at \(x),\(y) is outside the \(width)x\(height) screen")
        }
        guard data.count >= w * h * 4 else {
            throw RFBError.protocolViolation("raw rect is missing pixel data")
        }
        let rowBytes = w * 4
        let stride = bytesPerRow
        pixels.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                for row in 0..<h {
                    let dst = destination.baseAddress! + (y + row) * stride + x * 4
                    let src = source.baseAddress! + row * rowBytes
                    dst.copyMemory(from: src, byteCount: rowBytes)
                }
            }
        }
    }

    /// Moves an existing region of the screen (window drags, scrolling).
    func copyRect(fromX srcX: Int, fromY srcY: Int, toX x: Int, toY y: Int, width w: Int, height h: Int) throws {
        guard contains(x: srcX, y: srcY, width: w, height: h), contains(x: x, y: y, width: w, height: h) else {
            throw RFBError.protocolViolation("copy rect is outside the screen")
        }
        let rowBytes = w * 4
        let stride = bytesPerRow
        // Walk rows in the direction that never overwrites rows not yet copied.
        let rows: [Int] = y > srcY ? Array((0..<h).reversed()) : Array(0..<h)
        pixels.withUnsafeMutableBytes { buffer in
            let base = buffer.baseAddress!
            for row in rows {
                let src = base + (srcY + row) * stride + srcX * 4
                let dst = base + (y + row) * stride + x * 4
                memmove(dst, src, rowBytes)
            }
        }
    }

    func fill(x: Int, y: Int, width w: Int, height h: Int, pixel: UInt32) {
        pixels.withUnsafeMutableBytes { buffer in
            let base = buffer.baseAddress!.assumingMemoryBound(to: UInt32.self)
            for row in y..<(y + h) {
                let start = base + row * width + x
                start.update(repeating: pixel.littleEndian, count: w)
            }
        }
    }

    /// Gives decoders direct access to the pixel storage as 32-bit words.
    func withPixelWords<T>(_ body: (UnsafeMutablePointer<UInt32>, Int) throws -> T) rethrows -> T {
        try pixels.withUnsafeMutableBytes { buffer in
            try body(buffer.baseAddress!.assumingMemoryBound(to: UInt32.self), width)
        }
    }

    func makeImage() -> CGImage? {
        guard width > 0, height > 0,
              let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
