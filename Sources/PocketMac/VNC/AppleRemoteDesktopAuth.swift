import Foundation
import BigInt
import CommonCrypto
import CryptoKit

/// Apple Remote Desktop authentication (security type 30) — how macOS
/// Screen Sharing accepts your Mac account's username and password.
///
/// The server sends Diffie-Hellman parameters; both sides derive a shared
/// secret, its MD5 becomes an AES-128 key, and the credentials travel
/// encrypted with it.
enum AppleRemoteDesktopAuth {
    struct Challenge: Equatable {
        let generator: UInt16
        let keyLength: Int
        let prime: Data
        let serverPublicKey: Data
    }

    struct Response: Equatable {
        let encryptedCredentials: Data
        let clientPublicKey: Data

        var encoded: Data { encryptedCredentials + clientPublicKey }
    }

    static func response(
        to challenge: Challenge,
        username: String,
        password: String,
        privateKey: BigUInt? = nil,
        padding: Data? = nil
    ) -> Response {
        let prime = BigUInt(challenge.prime)
        let generator = BigUInt(challenge.generator)
        let serverPublic = BigUInt(challenge.serverPublicKey)
        let secret = privateKey ?? BigUInt.randomInteger(lessThan: prime - 2) + 1

        let clientPublic = generator.power(secret, modulus: prime)
        let shared = serverPublic.power(secret, modulus: prime)

        let aesKey = Data(Insecure.MD5.hash(data: leftPad(shared.serialize(), to: challenge.keyLength)))
        let credentials = credentialBlock(username: username, password: password, padding: padding)

        return Response(
            encryptedCredentials: aes128ECB(credentials, key: aesKey, operation: CCOperation(kCCEncrypt)),
            clientPublicKey: leftPad(clientPublic.serialize(), to: challenge.keyLength)
        )
    }

    /// 64 bytes of NUL-terminated username followed by 64 bytes of
    /// NUL-terminated password, the unused tail filled with random bytes.
    static func credentialBlock(username: String, password: String, padding: Data? = nil) -> Data {
        var block = padding ?? randomBytes(128)
        func write(_ string: String, at offset: Int) {
            let bytes = Array(string.utf8.prefix(63))
            for (index, byte) in bytes.enumerated() {
                block[block.startIndex + offset + index] = byte
            }
            block[block.startIndex + offset + bytes.count] = 0
        }
        write(username, at: 0)
        write(password, at: 64)
        return block
    }

    static func aes128ECB(_ data: Data, key: Data, operation: CCOperation) -> Data {
        var output = [UInt8](repeating: 0, count: data.count)
        var moved = 0
        let status = data.withUnsafeBytes { input in
            key.withUnsafeBytes { keyBytes in
                CCCrypt(
                    operation, CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionECBMode),
                    keyBytes.baseAddress, kCCKeySizeAES128, nil,
                    input.baseAddress, data.count,
                    &output, output.count, &moved
                )
            }
        }
        precondition(status == kCCSuccess, "AES failed: \(status)")
        return Data(output)
    }

    static func leftPad(_ data: Data, to length: Int) -> Data {
        guard data.count < length else { return data.suffix(length) }
        return Data(repeating: 0, count: length - data.count) + data
    }

    private static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }
}
