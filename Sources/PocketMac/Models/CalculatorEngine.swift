import Foundation

/// Pure arithmetic for the Calculator app, kept separate from the view so
/// the four-function logic can be unit tested without rendering SwiftUI.
enum CalculatorEngine {
    static func apply(_ op: String, _ lhs: Double, _ rhs: Double) -> Double {
        switch op {
        case "÷": return rhs == 0 ? 0 : lhs / rhs
        case "×": return lhs * rhs
        case "−": return lhs - rhs
        case "+": return lhs + rhs
        default: return rhs
        }
    }

    static func format(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%.6g", value)
    }
}
