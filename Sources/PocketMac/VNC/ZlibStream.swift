import Foundation
import zlib

/// A zlib inflate stream that lives for the whole connection (VNC keeps one
/// per encoding), inflating into a buffer reused between rectangles.
final class ZlibStream {
    private var stream = z_stream()
    private var isInitialized = false
    private var output = [UInt8]()

    deinit {
        if isInitialized { inflateEnd(&stream) }
    }

    /// Inflates `input` and returns how many bytes were produced; read them
    /// with `withOutput`.
    @_optimize(speed)
    func inflate(_ input: Data) throws -> Int {
        if !isInitialized {
            let status = inflateInit_(&stream, zlibVersion(), Int32(MemoryLayout<z_stream>.size))
            guard status == Z_OK else { throw RFBError.protocolViolation("zlib init failed (\(status))") }
            isInitialized = true
        }
        if output.count < max(input.count * 4, 64 * 1024) {
            output = [UInt8](repeating: 0, count: max(input.count * 4, 64 * 1024))
        }

        var produced = 0
        try input.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            while true {
                if produced == output.count {
                    output.append(contentsOf: [UInt8](repeating: 0, count: output.count))
                }
                let space = output.count - produced
                let status: Int32 = output.withUnsafeMutableBufferPointer { destination in
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

    func withOutput<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T {
        try output.withUnsafeBufferPointer(body)
    }
}
