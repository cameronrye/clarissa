import Foundation

/// Demo scenarios for App Store screenshots
enum DemoScenario: String {
    case welcome      // Empty state with suggestions
    case conversation // Calendar conversation
    case context      // Show context visualizer
    case settings     // Settings screen
}

/// Demo data for App Store screenshot mode
/// These curated conversations showcase the app's features in the best light
enum DemoData {

    /// Check if the app is running in screenshot/demo mode
    static var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-SCREENSHOT_MODE")
    }

    /// Current demo scenario based on launch arguments
    static var currentScenario: DemoScenario {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-DEMO_SCENARIO_WELCOME") {
            return .welcome
        } else if args.contains("-DEMO_SCENARIO_CONTEXT") {
            return .context
        } else if args.contains("-DEMO_SCENARIO_SETTINGS") {
            return .settings
        }
        // Default to conversation for basic screenshot mode
        return .conversation
    }

    /// Demo context stats for the context visualizer screenshot
    static let demoContextStats = ContextStats(
        currentTokens: 1847,
        maxTokens: 2296,
        usagePercent: 0.80,
        systemTokens: 300,
        userTokens: 520,
        assistantTokens: 927,
        toolTokens: 100,
        messageCount: 8,
        trimmedCount: 0
    )
    
    /// Demo messages for the main conversation screenshot
    static let conversationMessages: [ChatMessage] = [
        ChatMessage(role: .user, content: "What's on my calendar today?"),
        ChatMessage(role: .assistant, content: """
            You have 3 events today:
            
            **9:00 AM** - Team standup (30 min)
            **11:30 AM** - Lunch with Sarah at Cafe Luna
            **3:00 PM** - Product review meeting
            
            Your afternoon looks pretty open after the product review. Would you like me to help schedule anything?
            """),
        ChatMessage(role: .user, content: "Remind me to prepare the presentation before the 3pm meeting"),
        ChatMessage(role: .assistant, content: "I've created a reminder for 2:30 PM today to prepare your presentation before the product review meeting.")
    ]
    
    /// Demo messages showing tool usage
    static let toolsMessages: [ChatMessage] = [
        ChatMessage(role: .user, content: "What's the weather like this weekend?"),
        ChatMessage(
            role: .tool,
            content: "Weather data fetched successfully",
            toolName: "Checking weather",
            toolStatus: .completed
        ),
        ChatMessage(role: .assistant, content: """
            Here's your weekend forecast:
            
            **Saturday**: Sunny, 72°F - Perfect for outdoor activities!
            **Sunday**: Partly cloudy, 68°F - Slight chance of afternoon showers
            
            Looks like Saturday would be ideal if you're planning anything outdoors.
            """)
    ]
    
    /// Welcome screen suggestions (these appear as chips)
    /// Aligned with model capabilities - tool-oriented tasks the model can execute
    static let welcomeSuggestions = [
        "What's on my calendar?",
        "Set a reminder",
        "Check the weather",
        "Calculate a 20% tip"
    ]
    
    /// Convert demo ChatMessages to the format needed for display
    static func getConversationChatMessages() -> [ChatMessage] {
        return conversationMessages
    }
    
    static func getToolsChatMessages() -> [ChatMessage] {
        return toolsMessages
    }
}

