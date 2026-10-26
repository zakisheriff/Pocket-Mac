import XCTest
@testable import Pocket_Mac

final class CalculatorEngineTests: XCTestCase {

    func testAddSubtractMultiplyDivide() {
        XCTAssertEqual(CalculatorEngine.apply("+", 2, 3), 5)
        XCTAssertEqual(CalculatorEngine.apply("−", 5, 3), 2)
        XCTAssertEqual(CalculatorEngine.apply("×", 4, 3), 12)
        XCTAssertEqual(CalculatorEngine.apply("÷", 9, 3), 3)
    }

    func testDivideByZeroReturnsZeroInsteadOfCrashingOrInfinity() {
        XCTAssertEqual(CalculatorEngine.apply("÷", 9, 0), 0)
    }

    func testWholeNumbersFormatWithoutADecimalPoint() {
        XCTAssertEqual(CalculatorEngine.format(12), "12")
        XCTAssertEqual(CalculatorEngine.format(-4), "-4")
    }

    func testFractionalResultsKeepSignificantDigits() {
        XCTAssertEqual(CalculatorEngine.format(1.0 / 3.0), "0.333333")
    }
}
