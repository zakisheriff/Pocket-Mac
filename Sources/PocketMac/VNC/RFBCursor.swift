import CoreGraphics
import Foundation

/// The Mac's current mouse pointer shape, sent with the Cursor
/// pseudo-encoding so the phone can draw the pointer locally with no lag.
struct RFBCursor: Equatable {
    let image: CGImage
    let hotspot: CGPoint

    /// `pixels` is width×height BGRX; `mask` is one bit per pixel, rows
    /// padded to whole bytes, 1 = visible.
    init?(width: Int, height: Int, hotspotX: Int, hotspotY: Int, pixels: Data, mask: Data) {
        guard width > 0, height > 0 else { return nil }
        let maskRowBytes = (width + 7) / 8
        guard pixels.count >= width * height * 4, mask.count >= maskRowBytes * height else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let maskByte = mask[mask.startIndex + y * maskRowBytes + x / 8]
                guard maskByte & (0x80 >> UInt8(x % 8)) != 0 else { continue }
                let i = (y * width + x) * 4
                let source = pixels.startIndex + i
                rgba[i] = pixels[source]
                rgba[i + 1] = pixels[source + 1]
                rgba[i + 2] = pixels[source + 2]
                rgba[i + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }

        self.image = image
        hotspot = CGPoint(x: hotspotX, y: hotspotY)
    }

    static func == (lhs: RFBCursor, rhs: RFBCursor) -> Bool {
        lhs.image === rhs.image && lhs.hotspot == rhs.hotspot
    }
}
