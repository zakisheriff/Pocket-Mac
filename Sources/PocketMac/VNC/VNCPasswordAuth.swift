import Foundation
import CommonCrypto

/// Classic VNC authentication (security type 2): the server sends a 16-byte
/// challenge, the client DES-encrypts it with the password as the key.
/// Used by macOS when "VNC viewers may control screen with password" is set.
enum VNCPasswordAuth {
    static func response(challenge: Data, password: String) -> Data {
        precondition(challenge.count == 16, "VNC challenge must be 16 bytes")
        var key = [UInt8](repeating: 0, count: kCCKeySizeDES)
        for (index, byte) in password.utf8.prefix(8).enumerated() {
            key[index] = reverseBits(byte)
        }

        var output = [UInt8](repeating: 0, count: 16)
        var moved = 0
        let status = challenge.withUnsafeBytes { input in
            CCCrypt(
                CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmDES), CCOptions(kCCOptionECBMode),
                key, kCCKeySizeDES, nil,
                input.baseAddress, 16,
                &output, 16, &moved
            )
        }
        precondition(status == kCCSuccess, "DES encryption failed: \(status)")
        return Data(output)
    }

    /// VNC's quirk: each key byte is used with its bits mirrored.
    static func reverseBits(_ byte: UInt8) -> UInt8 {
        var input = byte
        var result: UInt8 = 0
        for _ in 0..<8 {
            result = (result << 1) | (input & 1)
            input >>= 1
        }
        return result
    }
}
