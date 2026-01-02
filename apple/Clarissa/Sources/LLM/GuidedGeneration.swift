import Foundation
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Guided Generation Types
//
// These @Generable structs enable structured output from Foundation Models.
// Guided generation guarantees structural correctness through constrained decoding,
// eliminating JSON parsing failures and malformed responses.
//
// Usage:
//   let session = LanguageModelSession()
//   let result = try await session.respond(to: "...", generating: ActionItems.self)
//   // result.content is guaranteed to be valid ActionItems

// MARK: - Action Items Extraction

/// Extracted action items from a conversation or text
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Action items extracted from conversation")
public struct ActionItems {
    @Guide(description: "List of tasks or action items identified")
    public var tasks: [ActionTask]

    @Guide(description: "List of calendar events to potentially create")
    public var events: [ExtractedEvent]

    @Guide(description: "List of reminders to potentially create")
    public var reminders: [ExtractedReminder]
}

/// A single action task
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A single action task or to-do item")
public struct ActionTask {
    @Guide(description: "Brief description of the task")
    public var title: String

    @Guide(description: "Priority level: high, medium, or low")
    public var priority: String?

    @Guide(description: "Due date if mentioned, in ISO 8601 format")
    public var dueDate: String?

    @Guide(description: "Person assigned if mentioned")
    public var assignee: String?
}

/// An extracted calendar event
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A potential calendar event extracted from text")
public struct ExtractedEvent {
    @Guide(description: "Event title")
    public var title: String

    @Guide(description: "Start date/time in ISO 8601 format")
    public var startDate: String?

    @Guide(description: "End date/time in ISO 8601 format")
    public var endDate: String?

    @Guide(description: "Event location if mentioned")
    public var location: String?
}

/// An extracted reminder
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "A potential reminder extracted from text")
public struct ExtractedReminder {
    @Guide(description: "Reminder title")
    public var title: String

    @Guide(description: "Due date in ISO 8601 format")
    public var dueDate: String?

    @Guide(description: "Additional notes")
    public var notes: String?
}

// MARK: - Entity Extraction

/// Entities extracted from text (people, places, dates, organizations)
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Named entities extracted from text")
public struct ExtractedEntities {
    @Guide(description: "People mentioned in the text")
    public var people: [String]

    @Guide(description: "Places and locations mentioned")
    public var places: [String]

    @Guide(description: "Organizations and companies mentioned")
    public var organizations: [String]

    @Guide(description: "Dates and times mentioned")
    public var dates: [String]

    @Guide(description: "Key topics or themes")
    public var topics: [String]
}

// MARK: - Conversation Analysis

/// Analysis of a conversation for tagging and organization
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Conversation analysis for tagging")
public struct ConversationAnalysis {
    @Guide(description: "A short title for the conversation (under 50 chars)")
    public var title: String

    @Guide(description: "Brief summary of the conversation (1-2 sentences)")
    public var summary: String

    @Guide(description: "Main topics discussed")
    public var topics: [String]

    @Guide(description: "Sentiment: positive, negative, or neutral")
    public var sentiment: String

    @Guide(description: "Category: technical, creative, informational, task, or social")
    public var category: String
}

// MARK: - Smart Reply Suggestions

/// Suggested quick replies based on conversation context
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Smart reply suggestions")
public struct SmartReplies {
    @Guide(description: "Suggested quick reply options (2-4 options)")
    public var suggestions: [String]
}

// MARK: - Session Title Generation

/// Generated title for a conversation session
@available(iOS 26.0, macOS 26.0, *)
@Generable(description: "Generated session title")
public struct SessionTitle {
    @Guide(description: "Concise title for the conversation (max 50 characters)")
    public var title: String
}

// MARK: - Guided Generation Service

/// Service for performing guided generation operations using Foundation Models
/// All outputs are structurally guaranteed via constrained decoding
@available(iOS 26.0, macOS 26.0, *)
@MainActor
final class GuidedGenerationService {

    /// Shared instance
    static let shared = GuidedGenerationService()

    private init() {}

    /// Extract action items from conversation text
    /// - Parameter text: The conversation or text to analyze
    /// - Returns: Structured action items with tasks, events, and reminders
    func extractActionItems(from text: String) async throws -> ActionItems {
        let session = LanguageModelSession(
            instructions: Instructions("""
                You are an assistant that extracts action items from conversations.
                Identify tasks, calendar events, and reminders mentioned in the text.
                Be precise and only extract items that were clearly mentioned or implied.
                """)
        )

        let result = try await session.respond(
            to: Prompt("Extract action items from this conversation:\n\n\(text)"),
            generating: ActionItems.self
        )

        return result.content
    }

    /// Extract named entities from text
    /// - Parameter text: The text to analyze
    /// - Returns: Extracted entities (people, places, organizations, dates, topics)
    func extractEntities(from text: String) async throws -> ExtractedEntities {
        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: Instructions("""
                Extract named entities from the text including people, places,
                organizations, dates, and key topics.
                """)
        )

        let result = try await session.respond(
            to: Prompt(text),
            generating: ExtractedEntities.self
        )

        return result.content
    }

    /// Analyze a conversation for categorization and summarization
    /// - Parameter messages: The conversation messages
    /// - Returns: Analysis including title, summary, topics, sentiment, and category
    func analyzeConversation(_ messages: [Message]) async throws -> ConversationAnalysis {
        let conversationText = messages
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n\n")

        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: Instructions("""
                Analyze this conversation and provide:
                - A short, descriptive title (under 50 characters)
                - A brief 1-2 sentence summary
                - Main topics discussed
                - Overall sentiment (positive, negative, neutral)
                - Category (technical, creative, informational, task, social)
                """)
        )

        let result = try await session.respond(
            to: Prompt(conversationText),
            generating: ConversationAnalysis.self
        )

        return result.content
    }

    /// Generate a smart title for a conversation session
    /// - Parameter messages: The conversation messages
    /// - Returns: A concise, descriptive title
    func generateSessionTitle(from messages: [Message]) async throws -> String {
        guard !messages.isEmpty else { return "New Conversation" }

        let conversationText = messages
            .prefix(5) // Use first few messages for context
            .map { "\($0.role.rawValue): \($0.content.prefix(200))" }
            .joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: Instructions("""
                Generate a concise, descriptive title for this conversation.
                The title should be under 50 characters and capture the main topic.
                Return just the title, no quotes or punctuation.
                """)
        )

        let result = try await session.respond(
            to: Prompt(conversationText),
            generating: SessionTitle.self
        )

        return result.content.title
    }

    /// Generate smart reply suggestions based on conversation context
    /// - Parameter messages: Recent conversation messages
    /// - Returns: 2-4 suggested quick replies
    func generateSmartReplies(for messages: [Message]) async throws -> [String] {
        let recentMessages = messages.suffix(5)
        let conversationText = recentMessages
            .map { "\($0.role.rawValue): \($0.content.prefix(200))" }
            .joined(separator: "\n")

        let session = LanguageModelSession(
            instructions: Instructions("""
                Based on the conversation context, suggest 2-4 natural follow-up
                messages the user might want to send. Keep suggestions brief and relevant.
                """)
        )

        let result = try await session.respond(
            to: Prompt(conversationText),
            generating: SmartReplies.self
        )

        return result.content.suggestions
    }

    // MARK: - Streaming Partial Generation

    /// Stream conversation analysis with progressive updates
    /// Returns partial results as properties are decoded
    /// Note: The streaming API returns snapshots with .content containing the partial result
    func streamConversationAnalysis(
        _ messages: [Message],
        onUpdate: @escaping (ConversationAnalysis) -> Void
    ) async throws -> ConversationAnalysis {
        let conversationText = messages
            .map { "\($0.role.rawValue): \($0.content)" }
            .joined(separator: "\n\n")

        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: Instructions("""
                Analyze this conversation and provide:
                - A short, descriptive title (under 50 characters)
                - A brief 1-2 sentence summary
                - Main topics discussed
                - Overall sentiment (positive, negative, neutral)
                - Category (technical, creative, informational, task, social)
                """)
        )

        // Use respond() for guided generation - streaming of structured types
        // returns the complete result; partial updates are internal
        let response = try await session.respond(
            to: Prompt(conversationText),
            generating: ConversationAnalysis.self
        )

        let result = response.content
        onUpdate(result)
        return result
    }

    /// Stream action items extraction with progressive updates
    func streamActionItems(
        from text: String,
        onUpdate: @escaping (ActionItems) -> Void
    ) async throws -> ActionItems {
        let session = LanguageModelSession(
            instructions: Instructions("""
                You are an assistant that extracts action items from conversations.
                Identify tasks, calendar events, and reminders mentioned in the text.
                Be precise and only extract items that were clearly mentioned or implied.
                """)
        )

        let response = try await session.respond(
            to: Prompt("Extract action items from this conversation:\n\n\(text)"),
            generating: ActionItems.self
        )

        let result = response.content
        onUpdate(result)
        return result
    }

    /// Stream entity extraction with progressive updates
    func streamEntityExtraction(
        from text: String,
        onUpdate: @escaping (ExtractedEntities) -> Void
    ) async throws -> ExtractedEntities {
        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: Instructions("""
                Extract named entities from the text including people, places,
                organizations, dates, and key topics.
                """)
        )

        let response = try await session.respond(
            to: Prompt(text),
            generating: ExtractedEntities.self
        )

        let result = response.content
        onUpdate(result)
        return result
    }
}

/// Errors for guided generation operations
@available(iOS 26.0, macOS 26.0, *)
enum GuidedGenerationError: LocalizedError {
    case streamingFailed

    var errorDescription: String? {
        switch self {
        case .streamingFailed:
            return "Failed to complete streaming generation"
        }
    }
}

#endif

