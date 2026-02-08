import Foundation

/// Callbacks for tool chain execution progress
@MainActor
protocol ToolChainCallbacks: AnyObject {
    /// Called when a chain step begins executing
    func onChainStepStart(stepIndex: Int, step: ToolChainStep)
    /// Called when a chain step completes
    func onChainStepComplete(stepIndex: Int, step: ToolChainStep, result: String, success: Bool)
    /// Called when all steps are done and results are being synthesized
    func onChainSynthesizing()
}

/// Default no-op implementations
extension ToolChainCallbacks {
    func onChainStepStart(stepIndex: Int, step: ToolChainStep) {}
    func onChainStepComplete(stepIndex: Int, step: ToolChainStep, result: String, success: Bool) {}
    func onChainSynthesizing() {}
}

/// Executes tool chains by running steps sequentially, piping outputs between steps.
///
/// Argument templates support `$N` and `$N.path` references:
/// - `$0` → raw output of step 0
/// - `$0.location` → the "location" field from step 0's JSON output
/// - `$input` → user-provided input string (for chains like Research & Save)
@MainActor
final class ToolChainExecutor {
    private let toolRegistry: ToolRegistry
    private weak var callbacks: ToolChainCallbacks?

    init(toolRegistry: ToolRegistry = .shared, callbacks: ToolChainCallbacks? = nil) {
        self.toolRegistry = toolRegistry
        self.callbacks = callbacks
    }

    /// Execute a tool chain, optionally skipping steps and providing user input.
    /// - Parameters:
    ///   - chain: The tool chain to execute
    ///   - skippedStepIds: Step IDs the user opted to skip in preview
    ///   - userInput: Optional user input for `$input` references
    /// - Returns: The complete chain result
    func execute(
        chain: ToolChain,
        skippedStepIds: Set<UUID> = [],
        userInput: String? = nil
    ) async throws -> ToolChainResult {
        let startTime = Date()
        var stepOutputs: [Int: String] = [:]  // stepIndex → result string
        var stepResults: [StepResult] = []
        var aborted = false

        for (index, step) in chain.steps.enumerated() {
            // Skip if user opted out
            if skippedStepIds.contains(step.id) {
                stepResults.append(StepResult(
                    stepId: step.id,
                    toolName: step.toolName,
                    label: step.label,
                    status: .skipped,
                    isOptional: step.isOptional
                ))
                continue
            }

            // Check for cancellation between steps
            try Task.checkCancellation()

            callbacks?.onChainStepStart(stepIndex: index, step: step)

            // Resolve argument references
            let resolvedArgs = resolveArguments(
                template: step.argumentTemplate,
                stepOutputs: stepOutputs,
                userInput: userInput
            )

            // Execute the tool
            do {
                let result = try await toolRegistry.execute(
                    name: step.toolName,
                    arguments: resolvedArgs
                )

                stepOutputs[index] = result
                stepResults.append(StepResult(
                    stepId: step.id,
                    toolName: step.toolName,
                    label: step.label,
                    status: .completed(result: result),
                    isOptional: step.isOptional
                ))

                callbacks?.onChainStepComplete(
                    stepIndex: index,
                    step: step,
                    result: result,
                    success: true
                )

                await AnalyticsCollector.shared.recordToolCall(name: step.toolName, success: true)

            } catch {
                let errorMessage = error.localizedDescription
                stepResults.append(StepResult(
                    stepId: step.id,
                    toolName: step.toolName,
                    label: step.label,
                    status: .failed(error: errorMessage),
                    isOptional: step.isOptional
                ))

                callbacks?.onChainStepComplete(
                    stepIndex: index,
                    step: step,
                    result: errorMessage,
                    success: false
                )

                await AnalyticsCollector.shared.recordToolCall(name: step.toolName, success: false)

                // Stop chain if a required step fails
                if !step.isOptional {
                    ClarissaLogger.agent.error("Chain '\(chain.id)' aborted at step \(index) (\(step.toolName)): \(errorMessage)")
                    aborted = true
                    break
                }
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        ClarissaLogger.agent.info("Chain '\(chain.id)' completed in \(String(format: "%.1f", duration))s (\(stepResults.filter { if case .completed = $0.status { return true }; return false }.count)/\(chain.steps.count) steps, aborted: \(aborted))")

        return ToolChainResult(
            chainId: chain.id,
            stepResults: stepResults,
            duration: duration,
            wasAborted: aborted
        )
    }

    // MARK: - Argument Resolution

    /// Resolve `$N`, `$N.path`, and `$input` references in an argument template
    private func resolveArguments(
        template: String,
        stepOutputs: [Int: String],
        userInput: String?
    ) -> String {
        var resolved = template

        // Replace $input with user-provided text
        if let userInput {
            resolved = resolved.replacingOccurrences(of: "\"$input\"", with: "\"\(escapeJSON(userInput))\"")
            resolved = resolved.replacingOccurrences(of: "$input", with: escapeJSON(userInput))
        }

        // Replace $N.path references (more specific, match first)
        // Pattern: $0.someField or $1.nested.field
        let pathPattern = #"\$(\d+)\.([a-zA-Z0-9_.]+)"#
        if let regex = try? NSRegularExpression(pattern: pathPattern) {
            let nsRange = NSRange(resolved.startIndex..., in: resolved)
            let matches = regex.matches(in: resolved, range: nsRange)

            // Process matches in reverse order to preserve indices
            for match in matches.reversed() {
                guard match.numberOfRanges >= 3,
                      let stepRange = Range(match.range(at: 1), in: resolved),
                      let pathRange = Range(match.range(at: 2), in: resolved),
                      let matchRange = Range(match.range, in: resolved),
                      let stepIndex = Int(resolved[stepRange]),
                      let output = stepOutputs[stepIndex] else { continue }

                let path = String(resolved[pathRange])
                let extracted = extractJSONValue(from: output, path: path)
                resolved = resolved.replacingCharacters(in: matchRange, with: extracted)
            }
        }

        // Replace bare $N references (entire step output)
        let barePattern = #""\$(\d+)""#
        if let regex = try? NSRegularExpression(pattern: barePattern) {
            let nsRange = NSRange(resolved.startIndex..., in: resolved)
            let matches = regex.matches(in: resolved, range: nsRange)

            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let stepRange = Range(match.range(at: 1), in: resolved),
                      let matchRange = Range(match.range, in: resolved),
                      let stepIndex = Int(resolved[stepRange]),
                      let output = stepOutputs[stepIndex] else { continue }

                // Truncate long outputs to stay within token budget
                let truncated = String(output.prefix(500))
                resolved = resolved.replacingCharacters(in: matchRange, with: "\"\(escapeJSON(truncated))\"")
            }
        }

        return resolved
    }

    /// Extract a value from a JSON string by dot-separated path
    private func extractJSONValue(from jsonString: String, path: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            ClarissaLogger.agent.warning("Chain argument piping: could not parse JSON for path '\(path)'")
            return jsonString
        }

        let components = path.split(separator: ".").map(String.init)
        var current: Any = json

        for component in components {
            // Check for array index: field[0]
            if let bracketRange = component.range(of: #"\[(\d+)\]"#, options: .regularExpression),
               let indexStr = component[bracketRange].dropFirst().dropLast().description as String?,
               let index = Int(indexStr) {
                let fieldName = String(component[..<bracketRange.lowerBound])
                if !fieldName.isEmpty, let dict = current as? [String: Any] {
                    current = dict[fieldName] ?? current
                }
                if let array = current as? [Any], index < array.count {
                    current = array[index]
                } else {
                    ClarissaLogger.agent.warning("Chain argument piping: array index out of bounds for path '\(path)' at component '\(component)'")
                    return ""
                }
            } else if let dict = current as? [String: Any] {
                guard let value = dict[component] else {
                    ClarissaLogger.agent.warning("Chain argument piping: key '\(component)' not found for path '\(path)'")
                    return ""
                }
                current = value
            } else {
                ClarissaLogger.agent.warning("Chain argument piping: unexpected type at component '\(component)' for path '\(path)'")
                return ""
            }
        }

        // Convert result to string
        if let string = current as? String {
            return string
        } else if let data = try? JSONSerialization.data(withJSONObject: current),
                  let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "\(current)"
    }

    /// Escape a string for safe JSON embedding using JSONSerialization
    private func escapeJSON(_ string: String) -> String {
        // Use JSONSerialization for correct handling of all control characters (U+0000–U+001F)
        // .fragmentsAllowed is required because bare strings aren't valid top-level JSON by default.
        guard let data = try? JSONSerialization.data(withJSONObject: string, options: .fragmentsAllowed),
              let json = String(data: data, encoding: .utf8) else {
            // Fallback to manual escaping if serialization fails
            return string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
        }
        // JSONSerialization wraps in quotes: "value" — strip them
        return String(json.dropFirst().dropLast())
    }
}
