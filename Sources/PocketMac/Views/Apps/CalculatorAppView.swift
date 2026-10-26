import SwiftUI

struct CalculatorAppView: View {
    @State private var display = "0"
    @State private var accumulator: Double = 0
    @State private var pendingOperator: String?
    @State private var awaitingOperand = false

    private let rows: [[String]] = [
        ["C", "±", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "="],
    ]

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Text(display)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)

            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        CalculatorKey(label: key, isWide: key == "0", isActive: pendingOperator == key && awaitingOperand) {
                            tap(key)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.black)
    }

    private func tap(_ key: String) {
        HapticsManager.tap()
        switch key {
        case "0"..."9":
            if awaitingOperand || display == "0" {
                display = key
                awaitingOperand = false
            } else {
                display += key
            }
        case ".":
            if !display.contains(".") { display += "." }
        case "C":
            display = "0"; accumulator = 0; pendingOperator = nil
        case "±":
            if let value = Double(display) { display = formatted(value * -1) }
        case "%":
            if let value = Double(display) { display = formatted(value / 100) }
        case "÷", "×", "−", "+":
            accumulator = Double(display) ?? 0
            pendingOperator = key
            awaitingOperand = true
        case "=":
            guard let op = pendingOperator, let rhs = Double(display) else { return }
            let result: Double
            switch op {
            case "÷": result = rhs == 0 ? 0 : accumulator / rhs
            case "×": result = accumulator * rhs
            case "−": result = accumulator - rhs
            case "+": result = accumulator + rhs
            default: result = rhs
            }
            display = formatted(result)
            pendingOperator = nil
            awaitingOperand = true
        default: break
        }
    }

    private func formatted(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%.6g", value)
    }
}

private struct CalculatorKey: View {
    let label: String
    var isWide = false
    var isActive = false
    let action: () -> Void

    private var isOperator: Bool { ["÷", "×", "−", "+", "="].contains(label) }
    private var isFunction: Bool { ["C", "±", "%"].contains(label) }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 20, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .frame(width: isWide ? 100 : nil, alignment: isWide ? .leading : .center)
                .padding(.leading, isWide ? 20 : 0)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isFunction ? .black : (isActive ? .orange : .white))
        .background(
            Circle()
                .fill(isActive ? Color.white : (isOperator ? Color.orange : (isFunction ? Color(white: 0.65) : Color(white: 0.22))))
        )
        .clipShape(isWide ? AnyShape(Capsule()) : AnyShape(Circle()))
    }
}
