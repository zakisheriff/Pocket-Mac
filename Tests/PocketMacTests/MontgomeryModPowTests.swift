import XCTest
import BigInt
@testable import Pocket_Mac

/// Cross-checks the app's fast Montgomery exponentiation against the
/// independent BigInt library.
final class MontgomeryModPowTests: XCTestCase {

    private func randomOdd(bytes: Int) -> BigUInt {
        var value = BigUInt.randomInteger(withExactWidth: bytes * 8)
        value |= 1
        return value
    }

    private func check(base: BigUInt, exponent: BigUInt, modulus: BigUInt, length: Int, file: StaticString = #filePath, line: UInt = #line) {
        let expected = AppleRemoteDesktopAuth.leftPad(base.power(exponent, modulus: modulus).serialize(), to: length)
        let actual = MontgomeryModPow.power(
            base: AppleRemoteDesktopAuth.leftPad(base.serialize(), to: length),
            exponent: exponent.serialize(),
            modulus: AppleRemoteDesktopAuth.leftPad(modulus.serialize(), to: length)
        )
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    func testMatchesBigIntAt1024Bits() {
        for _ in 0..<10 {
            let modulus = randomOdd(bytes: 128)
            check(base: BigUInt.randomInteger(lessThan: modulus), exponent: BigUInt.randomInteger(withMaximumWidth: 512), modulus: modulus, length: 128)
        }
    }

    func testMatchesBigIntAt4096BitsWithSmallGenerator() {
        for _ in 0..<3 {
            let modulus = randomOdd(bytes: 512)
            check(base: 5, exponent: BigUInt.randomInteger(withExactWidth: 512), modulus: modulus, length: 512)
            check(base: BigUInt.randomInteger(lessThan: modulus), exponent: BigUInt.randomInteger(withExactWidth: 512), modulus: modulus, length: 512)
        }
    }

    func testEdgeCases() {
        let modulus = randomOdd(bytes: 64)
        check(base: 7, exponent: 0, modulus: modulus, length: 64)
        check(base: 7, exponent: 1, modulus: modulus, length: 64)
        check(base: 0, exponent: 9, modulus: modulus, length: 64)
        check(base: modulus - 1, exponent: 2, modulus: modulus, length: 64)
    }

    func testMacOSSizedExchangeIsFast() {
        let modulus = randomOdd(bytes: 512)
        let start = Date()
        _ = MontgomeryModPow.power(
            base: AppleRemoteDesktopAuth.leftPad(BigUInt.randomInteger(lessThan: modulus).serialize(), to: 512),
            exponent: BigUInt.randomInteger(withExactWidth: 512).serialize(),
            modulus: AppleRemoteDesktopAuth.leftPad(modulus.serialize(), to: 512)
        )
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
}
