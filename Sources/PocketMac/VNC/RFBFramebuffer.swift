import CoreGraphics
import Foundation
import IOSurface

/// The client-side copy of the Mac's screen, kept in an IOSurface so the
/// display layer can show it straight from GPU-shared memory — no per-frame
/// image copies. Pixels are 32-bit BGRA with alpha forced opaque.
///
/// Written only from the session's receive loop; the display reads it
/// concurrently (a frame may briefly show a partial update, never stale data).
final class RFBFramebuffer {
    private(set) var width: Int
    private(set) var height: Int
    private(set) var surface: IOSurface?
    /// Row length in pixels (IOSurface may pad rows for alignment).
    private(set) var stride = 0

    static let opaque: UInt32 = 0xFF00_0000

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        allocate()
    }

    func resize(width: Int, height: Int) {
        self.width = width
        self.height = height
        allocate()
    }

    private func allocate() {
        guard width > 0, height > 0,
              let surface = IOSurface(properties: [
                .width: width,
                .height: height,
                .bytesPerElement: 4,
                .pixelFormat: 0x4247_5241, // 'BGRA'
              ]) else {
            surface = nil
            stride = 0
            return
        }
        self.surface = surface
        stride = surface.bytesPerRow / 4
        fill(x: 0, y: 0, width: width, height: height, pixel: 0)
    }

    func contains(x: Int, y: Int, width w: Int, height h: Int) -> Bool {
        x >= 0 && y >= 0 && w >= 0 && h >= 0 && x + w <= width && y + h <= height
    }

    /// Direct access to the pixel words (32-bit BGRA) and the row stride.
    @_optimize(speed)
    func withPixelWords<T>(_ body: (UnsafeMutablePointer<UInt32>, Int) throws -> T) rethrows -> T {
        guard let surface else {
            var empty: UInt32 = 0
            return try body(&empty, 0)
        }
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        return try body(surface.baseAddress.assumingMemoryBound(to: UInt32.self), stride)
    }

    /// Copies a rectangle of tightly packed BGRX pixels into place.
    @_optimize(speed)
    func blitRaw(x: Int, y: Int, width w: Int, height h: Int, data: Data) throws {
        guard contains(x: x, y: y, width: w, height: h) else {
            throw RFBError.protocolViolation("raw rect \(w)x\(h) at \(x),\(y) is outside the \(width)x\(height) screen")
        }
        guard data.count >= w * h * 4 else {
            throw RFBError.protocolViolation("raw rect is missing pixel data")
        }
        withPixelWords { pixels, stride in
            data.withUnsafeBytes { source in
                let base = source.baseAddress!
                for row in 0..<h {
                    let destination = pixels + (y + row) * stride + x
                    let sourceRow = base + row * w * 4
                    for column in 0..<w {
                        let value = sourceRow.loadUnaligned(fromByteOffset: column * 4, as: UInt32.self)
                        destination[column] = UInt32(littleEndian: value) | Self.opaque
                    }
                }
            }
        }
    }

    /// Moves an existing region of the screen (window drags, scrolling).
    @_optimize(speed)
    func copyRect(fromX srcX: Int, fromY srcY: Int, toX x: Int, toY y: Int, width w: Int, height h: Int) throws {
        guard contains(x: srcX, y: srcY, width: w, height: h), contains(x: x, y: y, width: w, height: h) else {
            throw RFBError.protocolViolation("copy rect is outside the screen")
        }
        withPixelWords { pixels, rowLength in
            // Walk rows in the direction that never overwrites rows not yet copied.
            let rows: [Int] = y > srcY ? Array((0..<h).reversed()) : Array(0..<h)
            for row in rows {
                memmove(pixels + (y + row) * rowLength + x, pixels + (srcY + row) * rowLength + srcX, w * 4)
            }
        }
    }

    @_optimize(speed)
    func fill(x: Int, y: Int, width w: Int, height h: Int, pixel: UInt32) {
        withPixelWords { pixels, stride in
            for row in y..<(y + h) {
                (pixels + row * stride + x).update(repeating: pixel | Self.opaque, count: w)
            }
        }
    }

    /// A CGImage that reads straight from the surface's memory — no copy.
    func makeLiveImage() -> CGImage? {
        surface.flatMap { Self.liveImage(of: $0, width: width, height: height) }
    }

    static func liveImage(of surface: IOSurface, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let retained = Unmanaged.passRetained(surface)
        guard let provider = CGDataProvider(
            dataInfo: retained.toOpaque(),
            data: surface.baseAddress,
            size: surface.bytesPerRow * height,
            releaseData: { info, _, _ in
                if let info { Unmanaged<IOSurface>.fromOpaque(info).release() }
            }
        ) else {
            retained.release()
            return nil
        }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: surface.bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// A copy of the screen as a CGImage (for tests and snapshots).
    func makeImage() -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        withPixelWords { pixels, stride in
            bytes.withUnsafeMutableBytes { destination in
                for row in 0..<height {
                    (destination.baseAddress! + row * width * 4)
                        .copyMemory(from: pixels + row * stride, byteCount: width * 4)
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
}
