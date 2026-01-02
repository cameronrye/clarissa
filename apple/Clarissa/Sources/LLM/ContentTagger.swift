import Foundation
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Content Tagging Types
//
// These types leverage Apple's specialized content tagging adapter,
// which is specifically trained for extraction tasks and outperforms
// the general model for topic detection, entity extraction, and sentiment analysis.

/// Tags extracted from content for categorization
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Content tags and categories")
public struct ContentTags {
    @Guide(description: "Main topics or themes (up to 5)")
    public var topics: [String]

    @Guide(description: "Detected emotions or tone (up to 3)")
    public var emotions: [String]

    @Guide(description: "Action verbs or requested actions (up to 3)")
    public var actions: [String]

    @Guide(description: "Overall category: question, request, statement, greeting, or other")
    public var category: String
}

/// Intent classification for user messages
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "User intent classification")
public struct UserIntent {
    @Guide(description: "Primary intent: question, task, information, chat, or command")
    public var primaryIntent: String

    @Guide(description: "Confidence level: high, medium, or low")
    public var confidence: String

    @Guide(description: "Suggested tools that might help (e.g., calendar, weather, calculator)")
    public var suggestedTools: [String]

    @Guide(description: "Is this a follow-up to a previous message?")
    public var isFollowUp: Bool
}

/// Urgency and priority assessment
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Priority assessment")
public struct PriorityAssessment {
    @Guide(description: "Urgency level: urgent, high, medium, low, or none")
    public var urgency: String

    @Guide(description: "Time sensitivity: immediate, today, this_week, no_deadline")
    public var timeSensitivity: String

    @Guide(description: "Suggested response priority: 1 (highest) to 5 (lowest)")
    public var responsePriority: Int
}

// MARK: - Content Tagger Service

/// Service for content tagging using Apple's specialized content tagging adapter
/// The content tagging model is specifically optimized for extraction tasks
@available(iOS 26.0, macOS 26.0, *)
@MainActor
public final class ContentTagger {

    /// Shared instance
    public static let shared = ContentTagger()

    private init() {}

    /// Tag content with topics, emotions, and actions
    /// Uses the specialized content tagging adapter for best results
    /// - Parameter text: The text to tag
    /// - Returns: Extracted tags including topics, emotions, actions, and category
    public func tagContent(_ text: String) async throws -> ContentTags {
        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: Instructions("""
                Analyze the text and extract:
                - Main topics or themes being discussed
                - Emotional tone or sentiment
                - Action verbs or requested actions
                - Overall category of the message
                Be concise and precise.
                """)
        )

        let result = try await session.respond(
            to: Prompt(text),
            generating: ContentTags.self
        )

        return result.content
    }

    /// Classify user intent to help with response routing
    /// - Parameter message: The user message to classify
    /// - Returns: Intent classification with suggested tools
    public func classifyIntent(_ message: String) async throws -> UserIntent {
        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: Instructions("""
                Classify the user's intent from their message.
                Determine what they're trying to accomplish and which tools might help.
                Available tools: calendar, reminders, weather, contacts, location, calculator, web_fetch.
                """)
        )

        let result = try await session.respond(
            to: Prompt(message),
            generating: UserIntent.self
        )

        return result.content
    }

    /// Assess priority and urgency of a request
    /// - Parameter text: The request text to assess
    /// - Returns: Priority and urgency assessment
    public func assessPriority(_ text: String) async throws -> PriorityAssessment {
        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: Instructions("""
                Assess the urgency and priority of this request.
                Consider time-sensitive language, deadlines mentioned, and importance indicators.
                """)
        )

        let result = try await session.respond(
            to: Prompt(text),
            generating: PriorityAssessment.self
        )

        return result.content
    }

    /// Quick topic extraction for session organization
    /// - Parameter text: Text to extract topics from
    /// - Returns: List of main topics (up to 5)
    public func extractTopics(from text: String) async throws -> [String] {
        let tags = try await tagContent(text)
        return tags.topics
    }
}

#endif

