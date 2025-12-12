import Foundation

/// System prompt for the prompt enhancement feature.
/// Instructs the LLM to improve prompts while preserving intent.
/// Uses direct, imperative instructions with examples for on-device models.
private let enhancementSystemPrompt = """
You are a text enhancer. The user will give you a question or request. Your job is to rewrite it to be clearer and more effective.

IMPORTANT: Output ONLY the improved version of the text. Nothing else.

Example:
User: "tell me about cats"
Output: "What are the key characteristics, behaviors, and care requirements for domestic cats as pets?"

Example:
User: "how do I cook rice"
Output: "What is the best method for cooking fluffy white rice on the stovetop, including the ideal water-to-rice ratio and cooking time?"

Rules:
- Add specific details and context
- Fix grammar and spelling
- Make it more precise
- Keep the original intent
- Output ONLY the enhanced text, no explanations
"""

/// Actor responsible for enhancing user prompts using an LLM provider.
/// Thread-safe and can be used from any context.
actor PromptEnhancer {
    /// Shared singleton instance
    static let shared = PromptEnhancer()

    private init() {}

    /// Enhances a user prompt using the provided LLM provider.
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

