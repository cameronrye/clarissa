import Foundation

/// Demo scenarios for Watch App Store screenshots (10 total for Ultra 3: 422x514px)
enum WatchDemoScenario: String, CaseIterable {
    // Core scenarios (1-5)
    case welcome        // 01: Welcome state with quick actions
    case response       // 02: Response display
    case quickActions   // 03: Quick actions grid
    case voiceInput     // 04: Voice input active
    case processing     // 05: Processing state

    // Additional scenarios (6-10)
    case history        // 06: Response history list
    case historyDetail  // 07: Response detail view
    case error          // 08: Error state with recovery
    case connected      // 09: Connected to iPhone state
    case sending        // 10: Sending query state
}

/// Demo data for Watch App Store screenshot mode
enum WatchDemoData {

    /// Check if the app is running in screenshot/demo mode
    static var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-SCREENSHOT_MODE")
    }

    /// Current demo scenario based on launch arguments
    static var currentScenario: WatchDemoScenario {
        let args = ProcessInfo.processInfo.arguments
        for scenario in WatchDemoScenario.allCases {
            let argName = "-DEMO_SCENARIO_\(scenario.rawValue.uppercased())"
            if args.contains(argName) {
                return scenario
            }
        }
        return .welcome
    }

    // MARK: - Demo Response History

    static let demoHistoryItems: [ResponseHistoryItem] = [
        ResponseHistoryItem(
            query: "What's the weather?",
            response: "Sunny, 72F. Perfect for a walk!"
        ),
        ResponseHistoryItem(
            query: "Next meeting?",
            response: "Team standup at 9:00 AM in 30 minutes."
        ),
        ResponseHistoryItem(
            query: "Set a timer",
            response: "Timer set for 5 minutes."
        ),
        ResponseHistoryItem(
            query: "Remind me to call Mom",
            response: "Reminder set for 6:00 PM today."
        ),
        ResponseHistoryItem(
            query: "What's on my calendar?",
            response: "You have 3 events today: Team standup at 9 AM, Lunch with Alex at 12 PM, and Dentist at 4 PM."
        )
    ]

    /// Get the first demo history item for response screenshot (weather)
    static var demoResponse: ResponseHistoryItem {
        demoHistoryItems[0]
    }

    /// Get a different response for connected screenshot (calendar)
    static var demoConnectedResponse: ResponseHistoryItem {
        demoHistoryItems[4]  // Calendar response - longer, more detailed
    }

    /// Demo error message for error state screenshot
    static let demoErrorMessage = "iPhone not reachable"

    /// Demo query for sending state
    static let demoSendingQuery = "What's the weather today?"
}

