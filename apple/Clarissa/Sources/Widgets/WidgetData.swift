import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - App Group Constants

/// Shared constants for app-widget communication
public enum ClarissaAppGroup {
    /// The App Group identifier shared between the main app and widgets
    public static let identifier = "group.dev.rye.clarissa"
    
    /// Shared UserDefaults for app-widget data exchange
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
    
    // MARK: - UserDefaults Keys
    
    /// Key for the last conversation message
    public static let lastMessageKey = "lastMessage"
    
    /// Key for the last response from Clarissa
    public static let lastResponseKey = "lastResponse"
    
    /// Key for the last conversation timestamp
    public static let lastUpdatedKey = "lastUpdated"
    
    /// Key for suggested quick questions
    public static let suggestedQuestionsKey = "suggestedQuestions"

    /// Key for morning widget data (weather + calendar + reminders)
    public static let morningDataKey = "morningWidgetData"

    /// Key for memory spotlight widget data
    public static let memorySpotlightKey = "memorySpotlightData"
}

// MARK: - Widget Data Models

/// Data shared between the main app and widgets
public struct WidgetConversationData: Codable, Sendable {
    /// The last user message
    public let lastMessage: String?
    
    /// The last response from Clarissa
    public let lastResponse: String?
    
    /// When the conversation was last updated
    public let lastUpdated: Date
    
    /// Suggested quick questions for the widget
    public let suggestedQuestions: [String]
    
    public init(
        lastMessage: String? = nil,
        lastResponse: String? = nil,
        lastUpdated: Date = Date(),
        suggestedQuestions: [String] = []
    ) {
        self.lastMessage = lastMessage
        self.lastResponse = lastResponse
        self.lastUpdated = lastUpdated
        self.suggestedQuestions = suggestedQuestions
    }
    
    /// Default suggested questions when no conversation history exists
    public static let defaultQuestions = [
        "What's the weather today?",
        "What's on my calendar?",
        "Set a reminder"
    ]
}

/// Data for the glanceable morning widget (weather + calendar + reminder)
public struct WidgetMorningData: Codable, Sendable {
    /// Short weather summary (e.g., "72°F, Sunny")
    public let weatherSummary: String?
    /// Next calendar event title
    public let nextEvent: String?
    /// Next calendar event start time
    public let nextEventTime: Date?
    /// Top reminder text
    public let topReminder: String?
    /// When this data was last refreshed
    public let lastUpdated: Date

    public init(
        weatherSummary: String? = nil,
        nextEvent: String? = nil,
        nextEventTime: Date? = nil,
        topReminder: String? = nil,
        lastUpdated: Date = Date()
    ) {
        self.weatherSummary = weatherSummary
        self.nextEvent = nextEvent
        self.nextEventTime = nextEventTime
        self.topReminder = topReminder
        self.lastUpdated = lastUpdated
    }
}

/// Data for the memory spotlight widget
public struct WidgetMemorySpotlight: Codable, Sendable {
    /// The memory content to display
    public let memoryContent: String
    /// Associated topics for display
    public let memoryTopics: [String]?
    /// Why this memory was surfaced (e.g., "Related to today's calendar")
    public let reason: String
    /// When this was last refreshed
    public let lastUpdated: Date

    public init(
        memoryContent: String,
        memoryTopics: [String]? = nil,
        reason: String = "",
        lastUpdated: Date = Date()
    ) {
        self.memoryContent = memoryContent
        self.memoryTopics = memoryTopics
        self.reason = reason
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Widget Data Manager

/// Manages reading and writing widget data from the shared App Group
@MainActor
public final class WidgetDataManager {
    public static let shared = WidgetDataManager()
    
    private init() {}
    
    /// Save conversation data for widgets to display
    public func saveConversationData(_ data: WidgetConversationData) {
        guard let defaults = ClarissaAppGroup.sharedDefaults else { return }
        
        defaults.set(data.lastMessage, forKey: ClarissaAppGroup.lastMessageKey)
        defaults.set(data.lastResponse, forKey: ClarissaAppGroup.lastResponseKey)
        defaults.set(data.lastUpdated, forKey: ClarissaAppGroup.lastUpdatedKey)
        
        if let encoded = try? JSONEncoder().encode(data.suggestedQuestions) {
            defaults.set(encoded, forKey: ClarissaAppGroup.suggestedQuestionsKey)
        }
        
        // Reload widgets to show new data
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    /// Load the latest conversation data for widgets
    public func loadConversationData() -> WidgetConversationData {
        guard let defaults = ClarissaAppGroup.sharedDefaults else {
            return WidgetConversationData(suggestedQuestions: WidgetConversationData.defaultQuestions)
        }
        
        let lastMessage = defaults.string(forKey: ClarissaAppGroup.lastMessageKey)
        let lastResponse = defaults.string(forKey: ClarissaAppGroup.lastResponseKey)
        let lastUpdated = defaults.object(forKey: ClarissaAppGroup.lastUpdatedKey) as? Date ?? Date()
        
        var suggestedQuestions = WidgetConversationData.defaultQuestions
        if let data = defaults.data(forKey: ClarissaAppGroup.suggestedQuestionsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            suggestedQuestions = decoded
        }
        
        return WidgetConversationData(
            lastMessage: lastMessage,
            lastResponse: lastResponse,
            lastUpdated: lastUpdated,
            suggestedQuestions: suggestedQuestions
        )
    }
    
    /// Update the last message and response after a conversation
    public func updateLastConversation(message: String, response: String) {
        let data = WidgetConversationData(
            lastMessage: message,
            lastResponse: response,
            lastUpdated: Date(),
            suggestedQuestions: WidgetConversationData.defaultQuestions
        )
        saveConversationData(data)
    }

    // MARK: - Morning Widget Data

    /// Save morning briefing data for the morning widget
    public func saveMorningData(_ data: WidgetMorningData) {
        guard let defaults = ClarissaAppGroup.sharedDefaults else { return }
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: ClarissaAppGroup.morningDataKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Load morning briefing data
    public func loadMorningData() -> WidgetMorningData? {
        guard let defaults = ClarissaAppGroup.sharedDefaults,
              let data = defaults.data(forKey: ClarissaAppGroup.morningDataKey) else { return nil }
        return try? JSONDecoder().decode(WidgetMorningData.self, from: data)
    }

    // MARK: - Memory Spotlight Widget Data

    /// Save memory spotlight data for the memory widget
    public func saveMemorySpotlight(_ data: WidgetMemorySpotlight) {
        guard let defaults = ClarissaAppGroup.sharedDefaults else { return }
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: ClarissaAppGroup.memorySpotlightKey)
        }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Load memory spotlight data
    public func loadMemorySpotlight() -> WidgetMemorySpotlight? {
        guard let defaults = ClarissaAppGroup.sharedDefaults,
              let data = defaults.data(forKey: ClarissaAppGroup.memorySpotlightKey) else { return nil }
        return try? JSONDecoder().decode(WidgetMemorySpotlight.self, from: data)
    }
}

