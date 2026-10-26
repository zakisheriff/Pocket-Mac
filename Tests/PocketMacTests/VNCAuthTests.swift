import XCTest
import BigInt
import CommonCrypto
import CryptoKit
@testable import Pocket_Mac

final class VNCPasswordAuthTests: XCTestCase {

    /// Reference computed independently with
    /// `openssl enc -des-ecb -nopad -K cea6c64ea62e8c4c` (the bit-reversed key).
    func testResponseMatchesOpenSSLReference() {
        let challenge = Data((0..<16).map { UInt8($0) })
        let response = VNCPasswordAuth.response(challenge: challenge, password: "secret12")
        XCTAssertEqual(response.hexString, "adcd997f8e16fee575e973f93c2b62b4")
    }

    func testOnlyTheFirstEightPasswordCharactersCount() {
        let challenge = Data(repeating: 7, count: 16)
        XCTAssertEqual(
            VNCPasswordAuth.response(challenge: challenge, password: "secret12"),
            VNCPasswordAuth.response(challenge: challenge, password: "secret12-and-more")
        )
    }

    func testBitReversal() {
        XCTAssertEqual(VNCPasswordAuth.reverseBits(0b0000_0001), 0b1000_0000)
        XCTAssertEqual(VNCPasswordAuth.reverseBits(0b1100_1010), 0b0101_0011)
    }
}

final class AppleRemoteDesktopAuthTests: XCTestCase {

    func testCredentialBlockLayout() {
        let block = AppleRemoteDesktopAuth.credentialBlock(
            username: "zaki", password: "hunter2", padding: Data(repeating: 0xAA, count: 128)
        )
        XCTAssertEqual(block.count, 128)
        XCTAssertEqual(Array(block[0..<5]), Array("zaki".utf8) + [0])
        XCTAssertEqual(block[5], 0xAA)
        XCTAssertEqual(Array(block[64..<72]), Array("hunter2".utf8) + [0])
        XCTAssertEqual(block[72], 0xAA)
    }

    /// Plays the Mac's side of the Diffie-Hellman exchange and checks the
    /// credentials decrypt back to what the client sent.
    func testServerCanDecryptTheCredentials() {
        let prime = TestDH.prime
        let serverSecret = BigUInt(0x1234_5678_9ABC_DEF0)
        let serverPublic = BigUInt(2).power(serverSecret, modulus: prime)
        let challenge = AppleRemoteDesktopAuth.Challenge(
            generator: 2, keyLength: 128,
            prime: AppleRemoteDesktopAuth.leftPad(prime.serialize(), to: 128),
            serverPublicKey: AppleRemoteDesktopAuth.leftPad(serverPublic.serialize(), to: 128)
        )

        let response = AppleRemoteDesktopAuth.response(to: challenge, username: "zaki", password: "correct horse")
        XCTAssertEqual(response.encryptedCredentials.count, 128)
        XCTAssertEqual(response.clientPublicKey.count, 128)

        let credentials = TestDH.decryptCredentials(response, serverSecret: serverSecret)
        XCTAssertEqual(credentials.username, "zaki")
        XCTAssertEqual(credentials.password, "correct horse")
    }

    /// Real macOS sends generator 5 with 512-byte (4096-bit) keys. Login
    /// must still decrypt correctly and stay quick at that size.
    func testMacOSSizedExchangeIsCorrectAndFast() {
        let prime = (BigUInt(1) << 4095) + BigUInt(0x1D)
        let serverSecret = BigUInt(0xFACE_B00C_1234)
        let serverPublic = BigUInt(5).power(serverSecret, modulus: prime)
        let challenge = AppleRemoteDesktopAuth.Challenge(
            generator: 5, keyLength: 512,
            prime: AppleRemoteDesktopAuth.leftPad(prime.serialize(), to: 512),
            serverPublicKey: AppleRemoteDesktopAuth.leftPad(serverPublic.serialize(), to: 512)
        )

        let start = Date()
        let response = AppleRemoteDesktopAuth.response(to: challenge, username: "afraasheriff", password: "pässwörd ✓")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(response.clientPublicKey.count, 512)
        let credentials = TestDH.decryptCredentials(response, serverSecret: serverSecret, prime: prime, keyLength: 512)
        XCTAssertEqual(credentials.username, "afraasheriff")
        XCTAssertEqual(credentials.password, "pässwörd ✓")
        XCTAssertLessThan(elapsed, 3, "login key exchange took \(elapsed)s")
    }
}

enum TestDH {
    /// RFC 2409 Oakley group 2 (1024-bit MODP), the size macOS uses.
    static let prime = BigUInt(
        "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B139B22514A08798E3404DDEF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7EDEE386BFB5A899FA5AE9F24117C4B1FE649286651ECE65381FFFFFFFFFFFFFFFF",
        radix: 16
    )!

    static func decryptCredentials(
        _ response: AppleRemoteDesktopAuth.Response,
        serverSecret: BigUInt,
        prime: BigUInt = TestDH.prime,
        keyLength: Int = 128
    ) -> (username: String, password: String) {
        let clientPublic = BigUInt(response.clientPublicKey)
        let shared = clientPublic.power(serverSecret, modulus: prime)
        let key = Data(Insecure.MD5.hash(data: AppleRemoteDesktopAuth.leftPad(shared.serialize(), to: keyLength)))
        let plain = AppleRemoteDesktopAuth.aes128ECB(response.encryptedCredentials, key: key, operation: CCOperation(kCCDecrypt))
        func string(at offset: Int) -> String {
            let bytes = plain[offset..<(offset + 64)].prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return (string(at: 0), string(at: 64))
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
