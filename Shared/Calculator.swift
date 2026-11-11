import Foundation

/// Evaluates simple arithmetic typed on the entry keypad, e.g. "12.5+3×2-1".
/// Supports + − × ÷ with normal precedence. Returns nil for invalid input.
enum Calculator {
    static let operators: Set<Character> = ["+", "−", "×", "÷"]

    static func evaluate(_ expression: String) -> Decimal? {
        var numbers: [Decimal] = []
        var ops: [Character] = []
        var current = ""

        for ch in expression {
            if operators.contains(ch) {
                if current.isEmpty {
                    // Leading minus, e.g. "−5"
                    if numbers.isEmpty && ch == "−" { current = "-"; continue }
                    return nil
                }
                guard let value = Decimal(string: current, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
                numbers.append(value)
                ops.append(ch)
                current = ""
            } else {
                current.append(ch)
            }
        }

        if current.isEmpty || current == "-" {
            // Trailing operator: ignore it.
            if !ops.isEmpty { ops.removeLast() }
        } else {
            guard let value = Decimal(string: current, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            numbers.append(value)
        }

        guard !numbers.isEmpty, numbers.count == ops.count + 1 else {
            return numbers.isEmpty ? 0 : nil
        }

        // Pass 1: × and ÷
        var terms: [Decimal] = [numbers[0]]
        var additive: [Character] = []
        for (index, op) in ops.enumerated() {
            let rhs = numbers[index + 1]
            switch op {
            case "×":
                terms[terms.count - 1] *= rhs
            case "÷":
                guard rhs != 0 else { return nil }
                terms[terms.count - 1] /= rhs
            default:
                additive.append(op)
                terms.append(rhs)
            }
        }

        // Pass 2: + and −
        var result = terms[0]
        for (index, op) in additive.enumerated() {
            result = op == "+" ? result + terms[index + 1] : result - terms[index + 1]
        }
        return result
    }

    static func containsOperator(_ expression: String) -> Bool {
        expression.dropFirst().contains(where: { operators.contains($0) })
    }
}

/// Keypad input state for the entry sheet.
struct KeypadInput: Equatable {
    private(set) var expression: String = ""

    init(cents: Int = 0) {
        if cents > 0 {
            expression = Money.decimal(cents).formatted(
                .number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))
            )
        }
    }

    var hasOperator: Bool { Calculator.containsOperator(expression) }

    var value: Decimal { Calculator.evaluate(expression) ?? 0 }

    var cents: Int { max(0, Money.cents(value)) }

    var isEmpty: Bool { expression.isEmpty }

    /// The number currently being typed (after the last operator).
    private var currentSegment: Substring {
        if let index = expression.lastIndex(where: { Calculator.operators.contains($0) }) {
            return expression[expression.index(after: index)...]
        }
        return expression[...]
    }

    mutating func type(_ key: String) {
        switch key {
        case "+", "−", "×", "÷":
            guard let last = expression.last else { return }
            if Calculator.operators.contains(last) {
                expression.removeLast()
            } else if last == "." {
                expression.removeLast()
            }
            expression.append(contentsOf: key)
        case ".":
            let segment = currentSegment
            guard !segment.contains(".") else { return }
            if segment.isEmpty { expression.append("0") }
            expression.append(".")
        default:
            let segment = currentSegment
            if let dot = segment.firstIndex(of: ".") {
                // Max two decimals
                guard segment.distance(from: dot, to: segment.endIndex) <= 2 else { return }
            } else {
                // Max 9 integer digits
                guard segment.count < 9 else { return }
                if segment == "0" {
                    expression.removeLast()
                }
            }
            expression.append(contentsOf: key)
        }
    }

    mutating func backspace() {
        if !expression.isEmpty { expression.removeLast() }
    }

    mutating func clear() { expression = "" }

    /// Collapses the expression into its evaluated result.
    mutating func commit() {
        let cents = self.cents
        self = KeypadInput(cents: cents)
    }
}
