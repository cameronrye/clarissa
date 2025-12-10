import Foundation

/// Tool for mathematical calculations
final class CalculatorTool: ClarissaTool, @unchecked Sendable {
    let name = "calculator"
    let description = "Evaluate mathematical expressions. Supports basic arithmetic (+, -, *, /), exponents (^), parentheses, and common math functions (sqrt, sin, cos, tan, log, abs, floor, ceil, round, pow) and constants (PI, E)."
    let priority = ToolPriority.core
    let requiresConfirmation = false

    /// Allowed characters in expressions for safety
    private let allowedCharacters = CharacterSet(charactersIn: "0123456789.+-*/^()%, ")
        .union(CharacterSet.letters)

    /// Maximum expression length
    private let maxExpressionLength = 500

    var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "expression": [
                    "type": "string",
                    "description": "The mathematical expression to evaluate"
                ]
            ],
            "required": ["expression"]
        ]
    }

    func execute(arguments: String) async throws -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expression = args["expression"] as? String else {
            throw ToolError.invalidArguments("Missing expression parameter")
        }

        // Validate expression
        try validateExpression(expression)

        do {
            let result = try evaluate(expression)
            let formatted = formatResult(result)

            let response: [String: Any] = [
                "expression": expression,
                "result": result,
                "formatted": formatted
            ]

            let responseData = try JSONSerialization.data(withJSONObject: response)
            return String(data: responseData, encoding: .utf8) ?? "{}"
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.executionFailed("Failed to evaluate expression: \(error.localizedDescription)")
        }
    }

    /// Validate expression for safety before evaluation
    private func validateExpression(_ expression: String) throws {
        // Check length
        guard expression.count <= maxExpressionLength else {
            throw ToolError.invalidArguments("Expression too long (max \(maxExpressionLength) characters)")
        }

        // Check for empty expression
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolError.invalidArguments("Expression cannot be empty")
        }

        // Check for balanced parentheses
        var parenCount = 0
        for char in expression {
            if char == "(" { parenCount += 1 }
            if char == ")" { parenCount -= 1 }
            if parenCount < 0 {
                throw ToolError.invalidArguments("Unbalanced parentheses in expression")
            }
        }
        if parenCount != 0 {
            throw ToolError.invalidArguments("Unbalanced parentheses in expression")
        }

        // Check for allowed characters only
        let allowedWords = ["sqrt", "sin", "cos", "tan", "log", "abs", "floor", "ceil", "round", "pow", "pi", "PI", "e", "E", "exp", "ln"]
        var checkExpr = expression.lowercased()
        for word in allowedWords {
            checkExpr = checkExpr.replacingOccurrences(of: word, with: "")
        }

        for scalar in checkExpr.unicodeScalars {
            if !allowedCharacters.contains(scalar) {
                throw ToolError.invalidArguments("Invalid character in expression: \(scalar)")
            }
        }
    }

    private func evaluate(_ expression: String) throws -> Double {
        // Prepare expression - handle common patterns
        var expr = expression
            .replacingOccurrences(of: "PI", with: "\(Double.pi)", options: .caseInsensitive)
            .replacingOccurrences(of: "^", with: "**")

        // Replace 'e' and 'E' only when they represent Euler's number (not part of scientific notation)
        expr = expr.replacingOccurrences(of: "(?<![0-9.])E(?![0-9+-])", with: "\(M_E)", options: .regularExpression)
        expr = expr.replacingOccurrences(of: "(?<![0-9.])e(?![0-9+-])", with: "\(M_E)", options: .regularExpression)

        // Handle math functions
        expr = try handleMathFunctions(expr)

        // Handle exponentiation
        if expr.contains("**") {
            return try evaluateWithPow(expr)
        }

        return try evaluateSimple(expr)
    }

    private func evaluateSimple(_ expr: String) throws -> Double {
        // Wrap in try-catch to handle NSExpression errors gracefully
        do {
            let nsExpression = NSExpression(format: expr)
            guard let result = nsExpression.expressionValue(with: nil, context: nil) as? NSNumber else {
                throw ToolError.executionFailed("Expression did not evaluate to a number")
            }
            return result.doubleValue
        } catch let error as ToolError {
            throw error
        } catch {
            throw ToolError.executionFailed("Invalid mathematical expression")
        }
    }

    private func handleMathFunctions(_ expr: String) throws -> String {
        var result = expr

        // Handle sqrt
        result = try replaceMathFunction(in: result, name: "sqrt") { sqrt($0) }

        // Handle sin (assumes radians)
        result = try replaceMathFunction(in: result, name: "sin") { sin($0) }

        // Handle cos
        result = try replaceMathFunction(in: result, name: "cos") { cos($0) }

        // Handle tan
        result = try replaceMathFunction(in: result, name: "tan") { tan($0) }

        // Handle log (natural log)
        result = try replaceMathFunction(in: result, name: "log") { log($0) }
        result = try replaceMathFunction(in: result, name: "ln") { log($0) }

        // Handle exp
        result = try replaceMathFunction(in: result, name: "exp") { exp($0) }

        // Handle abs
        result = try replaceMathFunction(in: result, name: "abs") { abs($0) }

        // Handle floor
        result = try replaceMathFunction(in: result, name: "floor") { floor($0) }

        // Handle ceil
        result = try replaceMathFunction(in: result, name: "ceil") { ceil($0) }

        // Handle round
        result = try replaceMathFunction(in: result, name: "round") { round($0) }

        return result
    }

    private func replaceMathFunction(in expr: String, name: String, operation: (Double) -> Double) throws -> String {
        var result = expr
        let pattern = "\(name)\\(([^)]+)\\)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return result
        }

        while let match = regex.firstMatch(in: result, options: [], range: NSRange(result.startIndex..., in: result)) {
            guard let argRange = Range(match.range(at: 1), in: result),
                  let fullRange = Range(match.range, in: result) else {
                break
            }

            let argString = String(result[argRange])
            let argValue = try evaluate(argString)
            let computedValue = operation(argValue)

            result.replaceSubrange(fullRange, with: "\(computedValue)")
        }

        return result
    }

    private func evaluateWithPow(_ expr: String) throws -> Double {
        // Handle exponentiation (right-to-left associative)
        if let range = expr.range(of: "**", options: .backwards) {
            let base = String(expr[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let exponent = String(expr[range.upperBound...]).trimmingCharacters(in: .whitespaces)

            guard !base.isEmpty && !exponent.isEmpty else {
                throw ToolError.invalidArguments("Invalid exponentiation expression")
            }

            let baseValue = try evaluate(base)
            let expValue = try evaluate(exponent)

            return pow(baseValue, expValue)
        }

        return try evaluateSimple(expr)
    }

    private func formatResult(_ result: Double) -> String {
        if result.isNaN {
            return "NaN (Not a Number)"
        }

        if result.isInfinite {
            return result > 0 ? "Infinity" : "-Infinity"
        }

        if result == result.rounded() && abs(result) < 1e15 {
            return String(format: "%.0f", result)
        }

        // Remove trailing zeros
        let formatted = String(format: "%.10f", result)
        return formatted.replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }
}

