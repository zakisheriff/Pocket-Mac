import Foundation

struct RFBPixelFormat: Equatable {
    var bitsPerPixel: UInt8
    var depth: UInt8
    var bigEndian: Bool
    var trueColor: Bool
    var redMax: UInt16
    var greenMax: UInt16
    var blueMax: UInt16
    var redShift: UInt8
    var greenShift: UInt8
    var blueShift: UInt8

    /// 32-bit little-endian 0x00RRGGBB — lands in memory as B,G,R,X, which
    /// Core Graphics draws directly as `byteOrder32Little | noneSkipFirst`.
    static let bgrx = RFBPixelFormat(
        bitsPerPixel: 32, depth: 24, bigEndian: false, trueColor: true,
        redMax: 255, greenMax: 255, blueMax: 255,
        redShift: 16, greenShift: 8, blueShift: 0
    )

    var bytesPerPixel: Int { Int(bitsPerPixel) / 8 }

    init(bitsPerPixel: UInt8, depth: UInt8, bigEndian: Bool, trueColor: Bool,
         redMax: UInt16, greenMax: UInt16, blueMax: UInt16,
         redShift: UInt8, greenShift: UInt8, blueShift: UInt8) {
        self.bitsPerPixel = bitsPerPixel
        self.depth = depth
        self.bigEndian = bigEndian
        self.trueColor = trueColor
        self.redMax = redMax
        self.greenMax = greenMax
        self.blueMax = blueMax
        self.redShift = redShift
        self.greenShift = greenShift
        self.blueShift = blueShift
    }

    init(data: Data) {
        bitsPerPixel = data[data.startIndex]
        depth = data[data.startIndex + 1]
        bigEndian = data[data.startIndex + 2] != 0
        trueColor = data[data.startIndex + 3] != 0
        redMax = data.bigEndianU16(at: 4)
        greenMax = data.bigEndianU16(at: 6)
        blueMax = data.bigEndianU16(at: 8)
        redShift = data[data.startIndex + 10]
        greenShift = data[data.startIndex + 11]
        blueShift = data[data.startIndex + 12]
    }

    var encoded: Data {
        var data = Data([bitsPerPixel, depth, bigEndian ? 1 : 0, trueColor ? 1 : 0])
        data.appendBE(redMax)
        data.appendBE(greenMax)
        data.appendBE(blueMax)
        data.append(contentsOf: [redShift, greenShift, blueShift, 0, 0, 0])
        return data
    }
}

enum RFBEncoding {
    static let raw: Int32 = 0
    static let copyRect: Int32 = 1
    static let hextile: Int32 = 5
    static let zlib: Int32 = 6
    static let zrle: Int32 = 16
    static let cursor: Int32 = -239
    static let desktopSize: Int32 = -223
    /// A standard server hint: spend less CPU compressing interactive updates.
    static let compressionLevel1: Int32 = -255
}

/// Both modes are lossless. Responsive avoids zlib work on the Mac;
/// Efficient trades more CPU work for less Wi-Fi traffic.
enum RFBStreamMode: String, CaseIterable, Identifiable {
    case responsive, efficient

    var id: String { rawValue }
    var displayName: String { self == .responsive ? "Responsive" : "Efficient" }

    var encodings: [Int32] {
        let pixels = self == .responsive
            ? [RFBEncoding.hextile, RFBEncoding.zrle, RFBEncoding.zlib]
            : [RFBEncoding.zrle, RFBEncoding.zlib, RFBEncoding.hextile]
        return [RFBEncoding.copyRect] + pixels + [
            RFBEncoding.raw, RFBEncoding.cursor, RFBEncoding.desktopSize, RFBEncoding.compressionLevel1,
        ]
    }
}

/// Mouse buttons as RFB button-mask bits. Scroll wheels are buttons 4–7,
/// sent as a press immediately followed by a release.
struct RFBButtons: OptionSet {
    let rawValue: UInt8
    static let left = RFBButtons(rawValue: 1 << 0)
    static let middle = RFBButtons(rawValue: 1 << 1)
    static let right = RFBButtons(rawValue: 1 << 2)
    static let wheelUp = RFBButtons(rawValue: 1 << 3)
    static let wheelDown = RFBButtons(rawValue: 1 << 4)
    static let wheelLeft = RFBButtons(rawValue: 1 << 5)
    static let wheelRight = RFBButtons(rawValue: 1 << 6)
}

/// Client → server messages (RFC 6143 §7.5).
enum RFBClientMessage {
    static func setPixelFormat(_ format: RFBPixelFormat) -> Data {
        Data([0, 0, 0, 0]) + format.encoded
    }

    static func setEncodings(_ encodings: [Int32]) -> Data {
        var data = Data([2, 0])
        data.appendBE(UInt16(encodings.count))
        for encoding in encodings { data.appendBE(encoding) }
        return data
    }

    static func framebufferUpdateRequest(incremental: Bool, x: UInt16, y: UInt16, width: UInt16, height: UInt16) -> Data {
        var data = Data([3, incremental ? 1 : 0])
        data.appendBE(x)
        data.appendBE(y)
        data.appendBE(width)
        data.appendBE(height)
        return data
    }

    static func keyEvent(keysym: UInt32, down: Bool) -> Data {
        var data = Data([4, down ? 1 : 0, 0, 0])
        data.appendBE(keysym)
        return data
    }

    static func pointerEvent(buttons: RFBButtons, x: UInt16, y: UInt16) -> Data {
        var data = Data([5, buttons.rawValue])
        data.appendBE(x)
        data.appendBE(y)
        return data
    }

    static func clientCutText(_ text: String) -> Data {
        let bytes = text.data(using: .isoLatin1, allowLossyConversion: true) ?? Data()
        var data = Data([6, 0, 0, 0])
        data.appendBE(UInt32(bytes.count))
        data.append(bytes)
        return data
    }
}
