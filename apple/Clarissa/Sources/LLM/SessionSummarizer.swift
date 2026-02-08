import Foundation
#if canImport(FoundationModels)
import FoundationModels

/// A concise summary of a conversation session
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A concise one-sentence conversation summary")
struct SessionSummaryResult {
    @Guide(description: "A one-sentence summary of the conversation, max 80 characters. Focus on the main topic or outcome.")
    var summary: String
}

/// Generates one-line summaries for conversation sessions using the content tagging adapter.
/// Summaries are shown in the history list to help users identify conversations at a glance.
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class SessionSummarizer {
    static let shared = SessionSummarizer()

    /// Minimum number of user messages before generating a summary
    private static let minimumUserMessages = 3

    private init() {}

    /// Generate a one-line summary for a set of messages.
    /// Returns nil if there isn't enough content to summarize.
    func summarize(messages: [Message]) async -> String? {
        let userMessages = messages.filter { $0.role == .user }
        guard userMessages.count >= Self.minimumUserMessages else { return nil }

        // Collect a representative sample: first 3 user messages + first 2 assistant messages
        let sampleUser = userMessages.prefix(3).map { "User: \($0.content)" }
        let sampleAssistant = messages.filter { $0.role == .assistant }.prefix(2).map { "Assistant: \($0.content)" }
        let sample = (sampleUser + sampleAssistant).joined(separator: "\n")

        // Truncate to stay within content tagging token limits
        let truncated = String(sample.prefix(800))

        do {
            let session = LanguageModelSession(
                model: SystemLanguageModel(useCase: .contentTagging),
                instructions: Instructions("""
                    Summarize this conversation in one concise sentence (max 80 characters).
                    Focus on the main topic, question, or outcome.
                    Do not include "The user..." — write it as a topic label.
                    Examples: "Weather check and calendar review for Monday", "Recipe ideas for dinner party"
                    """)
            )

            let result = try await session.respond(
                to: Prompt(truncated),
                generating: SessionSummaryResult.self
            )

            let summary = result.content.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? nil : String(summary.prefix(120))
        } catch {
            ClarissaLogger.provider.warning("Failed to generate session summary: \(error.localizedDescription)")
            return nil
        }
    }
}

#endif
