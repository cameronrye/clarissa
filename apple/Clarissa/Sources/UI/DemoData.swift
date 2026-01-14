import Foundation

/// Demo scenarios for App Store screenshots (10 total)
public enum DemoScenario: String, CaseIterable {
    case welcome              // 01: Empty state with suggestions
    case conversationCalendar // 02: Calendar conversation
    case conversationWeather  // 03: Weather query with tool result
    case conversationReminder // 04: Reminder creation
    case voiceMode            // 05: Voice input active
    case toolExecution        // 06: Tool running indicator
    case context              // 07: Context visualizer
    case history              // 08: Conversation history list
    case settingsProvider     // 09: Settings - provider selection
    case settingsVoice        // 10: Settings - voice configuration
}

/// Demo data for App Store screenshot mode
/// These curated conversations showcase the app's features in the best light
public enum DemoData {

    /// Check if the app is running in screenshot/demo mode
    public static var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-SCREENSHOT_MODE")
    }

    /// Current demo scenario based on launch arguments
    public static var currentScenario: DemoScenario {
        let args = ProcessInfo.processInfo.arguments
        for scenario in DemoScenario.allCases {
            let argName = "-DEMO_SCENARIO_\(scenario.rawValue.uppercased())"
            if args.contains(argName) {
                return scenario
            }
        }
        // Legacy support for old argument names
        if args.contains("-DEMO_SCENARIO_WELCOME") { return .welcome }
        if args.contains("-DEMO_SCENARIO_CONVERSATION") { return .conversationCalendar }
        if args.contains("-DEMO_SCENARIO_CONTEXT") { return .context }
        if args.contains("-DEMO_SCENARIO_SETTINGS") { return .settingsProvider }
        // Default to welcome for basic screenshot mode
        return .welcome
    }

    /// Demo context stats for the context visualizer screenshot
    /// Uses TokenBudget.maxHistoryTokens (1996) for accuracy
    static let demoContextStats = ContextStats(
        currentTokens: 1597,
        maxTokens: TokenBudget.maxHistoryTokens,
        usagePercent: 0.80,
        systemTokens: 300,
        userTokens: 450,
        assistantTokens: 1000,
        toolTokens: 147,
        messageCount: 8,
        trimmedCount: 0
    )

    // MARK: - Screenshot 02: Calendar Conversation

    static let calendarMessages: [ChatMessage] = [
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

    // MARK: - Screenshot 03: Weather Conversation

    static let weatherMessages: [ChatMessage] = [
        ChatMessage(role: .user, content: "What's the weather like this weekend?"),
        ChatMessage(
            role: .tool,
            content: "Weather data fetched successfully",
            toolName: "Checking weather",
            toolStatus: .completed
        ),
        ChatMessage(role: .assistant, content: """
            Here's your weekend forecast:

            **Saturday**: Sunny, 72F - Perfect for outdoor activities!
            **Sunday**: Partly cloudy, 68F - Slight chance of afternoon showers

            Looks like Saturday would be ideal if you're planning anything outdoors.
            """)
    ]

    // MARK: - Screenshot 04: Reminder Conversation

    static let reminderMessages: [ChatMessage] = [
        ChatMessage(role: .user, content: "Remind me to call Mom tomorrow at 5pm"),
        ChatMessage(role: .assistant, content: """
            Done! I've set a reminder for tomorrow at 5:00 PM to call Mom.

            You'll get a notification when it's time.
            """)
    ]

    // MARK: - Screenshot 05: Voice Mode Messages

    static let voiceModeMessages: [ChatMessage] = [
        ChatMessage(role: .user, content: "Tell me a fun fact about space"),
        ChatMessage(role: .assistant, content: """
            Here's a fascinating space fact:

            A day on Venus is longer than its year! Venus takes 243 Earth days to rotate once, but only 225 Earth days to orbit the Sun.

            This makes Venus unique in our solar system - it also rotates backwards compared to most planets!
            """)
    ]

    // MARK: - Screenshot 06: Tool Execution In Progress

    static let toolExecutionMessages: [ChatMessage] = [
        ChatMessage(role: .user, content: "What time is my next meeting?"),
        ChatMessage(
            role: .tool,
            content: "Checking calendar events...",
            toolName: "Looking up calendar",
            toolStatus: .running
        )
    ]

    // MARK: - Screenshot 08: History Demo Sessions

    /// Demo sessions for the history screenshot - shows realistic conversation history
    static var historyDemoSessions: [Session] {
        let now = Date()
        return [
            Session(
                title: "Weekend Weather Forecast",
                messages: [
                    .user("What's the weather this weekend?"),
                    .assistant("Saturday will be sunny at 72F, perfect for outdoor activities!")
                ],
                createdAt: now.addingTimeInterval(-3600),
                updatedAt: now.addingTimeInterval(-3600)
            ),
            Session(
                title: "Today's Schedule",
                messages: [
                    .user("What's on my calendar today?"),
                    .assistant("You have 3 events: Team standup at 9am, lunch at noon, and a meeting at 3pm.")
                ],
                createdAt: now.addingTimeInterval(-7200),
                updatedAt: now.addingTimeInterval(-7200)
            ),
            Session(
                title: "Quick Pasta Recipe",
                messages: [
                    .user("How do I make a quick pasta?"),
                    .assistant("Boil pasta, sautee garlic in olive oil, toss with parmesan and fresh basil!")
                ],
                createdAt: now.addingTimeInterval(-86400),
                updatedAt: now.addingTimeInterval(-86400)
            ),
            Session(
                title: "Tip Calculator",
                messages: [
                    .user("What's 20% tip on $62.50?"),
                    .assistant("A 20% tip on $62.50 would be $12.50, making the total $75.00.")
                ],
                createdAt: now.addingTimeInterval(-172800),
                updatedAt: now.addingTimeInterval(-172800)
            ),
            Session(
                title: "Tokyo Travel Tips",
                messages: [
                    .user("Best places to visit in Tokyo?"),
                    .assistant("Must-see spots: Shibuya Crossing, Senso-ji Temple, and Harajuku for fashion!")
                ],
                createdAt: now.addingTimeInterval(-259200),
                updatedAt: now.addingTimeInterval(-259200)
            ),
            Session(
                title: "Meeting Reminder",
                messages: [
                    .user("Remind me about the project deadline"),
                    .assistant("I've set a reminder for Friday at 2pm about your project deadline.")
                ],
                createdAt: now.addingTimeInterval(-345600),
                updatedAt: now.addingTimeInterval(-345600)
            )
        ]
    }

    /// Welcome screen suggestions (these appear as chips)
    /// Aligned with model capabilities - tool-oriented tasks the model can execute
    static let welcomeSuggestions = [
        "What's on my calendar?",
        "Set a reminder",
        "Check the weather",
        "Calculate a 20% tip"
    ]

    /// Get messages for the current scenario
    static func getMessagesForScenario(_ scenario: DemoScenario) -> [ChatMessage] {
        switch scenario {
        case .welcome:
            return []
        case .conversationCalendar:
            return calendarMessages
        case .conversationWeather:
            return weatherMessages
        case .conversationReminder:
            return reminderMessages
        case .voiceMode:
            return voiceModeMessages
        case .toolExecution:
            return toolExecutionMessages
        case .context:
            return calendarMessages // Context visualizer shows with calendar messages
        case .history, .settingsProvider, .settingsVoice:
            return []
        }
    }

    // MARK: - Legacy Support

    /// Convert demo ChatMessages to the format needed for display
    static func getConversationChatMessages() -> [ChatMessage] {
        return calendarMessages
    }

    static func getToolsChatMessages() -> [ChatMessage] {
        return weatherMessages
    }
}

