import Foundation

/// Fast `base ^ exponent mod modulus` for Diffie-Hellman login, using
/// Montgomery multiplication on 64-bit words. macOS Screen Sharing uses a
/// 4096-bit group; a generic big-integer library is far too slow for that
/// in unoptimised builds, so this is always compiled for speed.
///
/// All numbers are big-endian byte strings. The modulus must be odd
/// (true for every DH prime). The result is left-padded to the modulus length.
enum MontgomeryModPow {
    @_optimize(speed)
    static func power(base: Data, exponent: Data, modulus: Data) -> Data {
        let n = (modulus.count + 7) / 8
        precondition(n > 0 && modulus.last.map { $0 & 1 == 1 } == true, "modulus must be odd")

        let m = limbs(modulus, count: n)
        var b = limbs(base.suffix(n * 8), count: n)
        let mPrime = negativeInverse(m[0])

        // R mod m and R² mod m, by doubling from 1 (R = 2^(64n)).
        var rModM = [UInt64](repeating: 0, count: n)
        rModM[0] = 1
        for _ in 0..<(64 * n) { doubleMod(&rModM, m) }
        var r2ModM = rModM
        for _ in 0..<(64 * n) { doubleMod(&r2ModM, m) }

        let baseMont = montgomeryMultiply(&b, &r2ModM, m, mPrime)
        var result = rModM // 1 in Montgomery form
        var baseCopy = baseMont

        let exponentBytes = [UInt8](exponent)
        var started = false
        for byte in exponentBytes {
            for bit in stride(from: 7, through: 0, by: -1) {
                if started {
                    var square = result
                    result = montgomeryMultiply(&square, &result, m, mPrime)
                }
                if (byte >> UInt8(bit)) & 1 == 1 {
                    result = started ? montgomeryMultiply(&result, &baseCopy, m, mPrime) : baseMont
                    started = true
                }
            }
        }
        if !started {
            result = rModM
        }

        var one = [UInt64](repeating: 0, count: n)
        one[0] = 1
        let plain = montgomeryMultiply(&result, &one, m, mPrime)
        return bytes(plain, length: modulus.count)
    }

    // MARK: - Arithmetic

    /// -m⁻¹ mod 2⁶⁴ by Newton iteration (m odd).
    @_optimize(speed)
    private static func negativeInverse(_ m0: UInt64) -> UInt64 {
        var inverse: UInt64 = 1
        for _ in 0..<6 { inverse = inverse &* (2 &- m0 &* inverse) }
        return 0 &- inverse
    }

    /// x = 2x mod m, for x < m.
    @_optimize(speed)
    private static func doubleMod(_ x: inout [UInt64], _ m: [UInt64]) {
        var carry: UInt64 = 0
        for i in 0..<x.count {
            let next = x[i] >> 63
            x[i] = (x[i] << 1) | carry
            carry = next
        }
        if carry == 1 || !isLess(x, m) { subtract(&x, m) }
    }

    /// a · b · R⁻¹ mod m (CIOS method). Inputs need not be fully reduced as
    /// long as they are below R; the result is always < m.
    @_optimize(speed)
    private static func montgomeryMultiply(_ a: inout [UInt64], _ b: inout [UInt64], _ m: [UInt64], _ mPrime: UInt64) -> [UInt64] {
        let n = m.count
        var t = [UInt64](repeating: 0, count: n + 2)

        a.withUnsafeBufferPointer { a in
        b.withUnsafeBufferPointer { b in
        m.withUnsafeBufferPointer { m in
        t.withUnsafeMutableBufferPointer { t in
            for i in 0..<n {
                let bi = b[i]
                var carry: UInt64 = 0
                for j in 0..<n {
                    let (high, low) = a[j].multipliedFullWidth(by: bi)
                    let (sum1, overflow1) = t[j].addingReportingOverflow(low)
                    let (sum2, overflow2) = sum1.addingReportingOverflow(carry)
                    t[j] = sum2
                    carry = high &+ (overflow1 ? 1 : 0) &+ (overflow2 ? 1 : 0)
                }
                let (top, topOverflow) = t[n].addingReportingOverflow(carry)
                t[n] = top
                t[n + 1] = topOverflow ? 1 : 0

                let factor = t[0] &* mPrime
                let (high0, low0) = m[0].multipliedFullWidth(by: factor)
                let (_, overflow0) = t[0].addingReportingOverflow(low0)
                carry = high0 &+ (overflow0 ? 1 : 0)
                for j in 1..<n {
                    let (high, low) = m[j].multipliedFullWidth(by: factor)
                    let (sum1, overflow1) = t[j].addingReportingOverflow(low)
                    let (sum2, overflow2) = sum1.addingReportingOverflow(carry)
                    t[j - 1] = sum2
                    carry = high &+ (overflow1 ? 1 : 0) &+ (overflow2 ? 1 : 0)
                }
                let (shifted, shiftedOverflow) = t[n].addingReportingOverflow(carry)
                t[n - 1] = shifted
                t[n] = t[n + 1] &+ (shiftedOverflow ? 1 : 0)
                t[n + 1] = 0
            }
        }}}}

        var result = Array(t[0..<n])
        if t[n] != 0 || !isLess(result, m) { subtract(&result, m) }
        return result
    }

    @_optimize(speed)
    private static func isLess(_ a: [UInt64], _ b: [UInt64]) -> Bool {
        for i in stride(from: a.count - 1, through: 0, by: -1) where a[i] != b[i] {
            return a[i] < b[i]
        }
        return false
    }

    /// a -= b, ignoring the final borrow (callers only subtract when a ≥ b mod 2^(64n)).
    @_optimize(speed)
    private static func subtract(_ a: inout [UInt64], _ b: [UInt64]) {
        var borrow: UInt64 = 0
        for i in 0..<a.count {
            let (difference1, overflow1) = a[i].subtractingReportingOverflow(b[i])
            let (difference2, overflow2) = difference1.subtractingReportingOverflow(borrow)
            a[i] = difference2
            borrow = (overflow1 ? 1 : 0) &+ (overflow2 ? 1 : 0)
        }
    }

    // MARK: - Conversion

    /// Big-endian bytes → little-endian 64-bit limbs.
    private static func limbs(_ data: Data, count: Int) -> [UInt64] {
        var result = [UInt64](repeating: 0, count: count)
        let bytes = [UInt8](data)
        for (index, byte) in bytes.reversed().enumerated() where index < count * 8 {
            result[index / 8] |= UInt64(byte) << UInt64((index % 8) * 8)
        }
        return result
    }

    private static func bytes(_ limbs: [UInt64], length: Int) -> Data {
        var result = [UInt8](repeating: 0, count: length)
        for index in 0..<length {
            let limb = index / 8
            guard limb < limbs.count else { break }
            result[length - 1 - index] = UInt8(truncatingIfNeeded: limbs[limb] >> UInt64((index % 8) * 8))
        }
        return Data(result)
    }
}
