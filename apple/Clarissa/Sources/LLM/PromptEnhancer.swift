import Foundation

/// System prompt for the prompt enhancement feature.
/// Optimized for Apple's on-device model - focuses on clarity for tool execution.
/// Keeps prompts short and direct rather than making them verbose.
private let enhancementSystemPrompt = """
Rewrite the user's request to be clearer. Output ONLY the rewritten text.

Example:
User: "weather"
Output: "What's the weather right now?"

Example:
User: "remind me about the thing tomorrow"
Output: "Set a reminder for tomorrow"

Example:
User: "whats 15% of 50 dolars"
Output: "What's 15% of $50?"

Rules:
- Keep it short and direct
- Fix typos and grammar
- Add missing context (like "current" for weather)
- Output ONLY the improved text
"""

/// Keywords that indicate the prompt is already clear enough for tool use
private let clearToolTriggers = [
    "weather", "forecast", "temperature",
    "remind", "reminder", "task",
    "calendar", "schedule", "meeting", "event", "appointment",
    "calculate", "what's", "what is", "how much", "percent", "tip",
    "contact", "phone", "email", "call",
    "where am i", "location", "address",
    "remember that", "don't forget"
]

/// Actor responsible for enhancing user prompts using an LLM provider.
/// Thread-safe and can be used from any context.
actor PromptEnhancer {
    /// Shared singleton instance
    static let shared = PromptEnhancer()

    private init() {}

    /// Check if a prompt is already clear enough and doesn't need enhancement
    private func isAlreadyClear(_ prompt: String) -> Bool {
        let lowercased = prompt.lowercased()

        // Skip if prompt contains clear tool triggers
        for trigger in clearToolTriggers {
            if lowercased.contains(trigger) {
                return true
            }
        }

        // Skip very short prompts that are likely already direct
        // (e.g., "weather?" or "my calendar")
        if prompt.count <= 15 {
            return true
        }

        return false
    }

    /// Enhances a user prompt using the provided LLM provider.
    /// Skips enhancement for prompts that are already clear or tool-triggering.
    ///
    /// - Parameters:
    ///   - prompt: The original prompt text to enhance
    ///   - provider: The LLM provider to use for enhancement
    /// - Returns: The enhanced prompt text
    /// - Throws: Any errors from the LLM provider
    func enhance(_ prompt: String, using provider: any LLMProvider) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return prompt
        }

        // Skip enhancement for already-clear prompts
        if isAlreadyClear(trimmedPrompt) {
            ClarissaLogger.agent.info("Prompt already clear, skipping enhancement")
            return prompt
        }

        ClarissaLogger.agent.info("Enhancing prompt: \(trimmedPrompt.prefix(50), privacy: .public)...")

        // Send the raw prompt text - the system instructions handle the task
        // Avoid prefixes like "Enhance this:" which confuse smaller on-device models
        let messages: [Message] = [
            .system(enhancementSystemPrompt),
            .user(trimmedPrompt)
        ]

        // Use the provider without tools for simple text generation
        let response = try await provider.complete(messages: messages, tools: [])

        var enhanced = response.content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clean up any stray LLM artifacts that may have leaked through
        enhanced = cleanLLMOutput(enhanced)

        ClarissaLogger.agent.info("Prompt enhanced successfully")

        // Return enhanced text, or original if response is empty
        return enhanced.isEmpty ? prompt : enhanced
    }

    /// Clean up LLM output by removing function call syntax, executable tags, and common preambles
    private func cleanLLMOutput(_ text: String) -> String {
        var result = text

        // Remove executable tags like <executable_end>, <exe>, etc.
        let executablePatterns = [
            "<executable_end>",
            "<exe>",
            "</exe>",
            "<executable>",
            "</executable>",
            "```executable",
            "```function"
        ]
        for pattern in executablePatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }

        // Remove function call JSON blocks with backticks
        // Pattern: ```function ... ``` or ```json ... ``` containing function calls
        if let range = result.range(of: "```(?:function|json)?\\s*\\[\\{\"name\":[^`]+```", options: .regularExpression) {
            result.removeSubrange(range)
        }

        // Remove bare function call arrays like [{"name": "...", "arguments": ...}]
        if let range = result.range(of: "\\[\\{\"name\":\\s*\"[^\"]+\",\\s*\"arguments\":[^\\]]+\\}\\]", options: .regularExpression) {
            result.removeSubrange(range)
        }

        // Clean up any resulting whitespace issues
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading/trailing backticks if the result is wrapped in code blocks
        if result.hasPrefix("```") && result.hasSuffix("```") {
            result = String(result.dropFirst(3).dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Remove common LLM preamble phrases that shouldn't appear in enhanced prompts
        let preamblePatterns = [
            "^Here is the (?:enhanced|improved|rewritten) (?:prompt|text|version)[:\\s]*",
            "^Here's the (?:enhanced|improved|rewritten) (?:prompt|text|version)[:\\s]*",
            "^Enhanced (?:prompt|version|text)[:\\s]*",
            "^Improved (?:prompt|version|text)[:\\s]*",
            "^Rewritten[:\\s]*",
            "^Sure[,!]?\\s*",
            "^Certainly[,!]?\\s*",
            "^Of course[,!]?\\s*",
            // Catch meta-instructions about enhancement (model outputting instructions instead of doing it)
            "^Enhance the prompt[^.]*\\.\\s*",
            "^To enhance this[^.]*\\.\\s*",
            "^Output[:\\s]*"
        ]
        for pattern in preamblePatterns {
            if let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                result.removeSubrange(range)
                result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Remove quotes if the entire result is wrapped in them
        if (result.hasPrefix("\"") && result.hasSuffix("\"")) ||
           (result.hasPrefix("'") && result.hasSuffix("'")) {
            result = String(result.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return result
    }
}

