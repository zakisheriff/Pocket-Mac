import UIKit

/// Draws the phone-side pointer in each style at any size.
enum PointerImages {
    /// Where the click lands, as a fraction of the image size.
    static func hotspot(for style: PointerStyle) -> CGPoint {
        switch style {
        case .macArrow, .whiteArrow: return CGPoint(x: 0.1, y: 0.07)
        case .ring, .dot: return CGPoint(x: 0.5, y: 0.5)
        }
    }

    /// Image size for a pointer of the given size setting.
    static func size(for style: PointerStyle, pointerSize: CGFloat) -> CGSize {
        switch style {
        case .macArrow, .whiteArrow: return CGSize(width: pointerSize * 0.68, height: pointerSize)
        case .ring: return CGSize(width: pointerSize, height: pointerSize)
        case .dot: return CGSize(width: pointerSize * 0.6, height: pointerSize * 0.6)
        }
    }

    private static var cache: [String: UIImage] = [:]

    static func image(for style: PointerStyle, pointerSize: CGFloat) -> UIImage {
        let key = "\(style.rawValue)-\(Int(pointerSize.rounded()))"
        if let cached = cache[key] { return cached }
        let size = size(for: style, pointerSize: pointerSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            switch style {
            case .macArrow, .whiteArrow:
                let path = arrowPath(in: rect.insetBy(dx: size.width * 0.06, dy: size.height * 0.04))
                path.lineJoinStyle = .round
                let fill: UIColor = style == .macArrow ? .black : .white
                let outline: UIColor = style == .macArrow ? .white : .black
                cg.setShadow(offset: CGSize(width: 0, height: size.height * 0.03), blur: size.height * 0.08,
                             color: UIColor(white: 0, alpha: 0.4).cgColor)
                outline.setStroke()
                path.lineWidth = max(1.4, size.height * 0.085)
                path.stroke()
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                fill.setFill()
                path.fill()
            case .ring:
                let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
                UIColor(white: 0.5, alpha: 0.28).setFill()
                ring.fill()
                UIColor(white: 1, alpha: 0.9).setStroke()
                ring.lineWidth = 1.5
                ring.stroke()
            case .dot:
                let dot = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
                cg.setShadow(offset: .zero, blur: 3, color: UIColor(white: 0, alpha: 0.5).cgColor)
                UIColor.white.setFill()
                dot.fill()
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                UIColor.systemBlue.setFill()
                UIBezierPath(ovalIn: rect.insetBy(dx: size.width * 0.28, dy: size.height * 0.28)).fill()
            }
        }
        cache[key] = image
        return image
    }

    /// The classic macOS arrow, scaled into `rect`.
    private static func arrowPath(in rect: CGRect) -> UIBezierPath {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 13 * rect.width, y: rect.minY + y / 20 * rect.height)
        }
        let path = UIBezierPath()
        path.move(to: point(0.5, 0.5))
        path.addLine(to: point(0.5, 16.5))
        path.addLine(to: point(4.4, 12.8))
        path.addLine(to: point(7.2, 19.2))
        path.addLine(to: point(9.9, 18.0))
        path.addLine(to: point(7.2, 11.8))
        path.addLine(to: point(12.5, 11.8))
        path.close()
        return path
    }
}
