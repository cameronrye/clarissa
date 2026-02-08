import AppIntents
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Individual Tool Shortcuts Actions

/// Exposes individual Clarissa tools as standalone Shortcuts actions.
/// Users can chain these in their own automations without a chat prompt.

// MARK: - Get Weather

@available(iOS 16.0, macOS 13.0, *)
struct GetWeatherShortcut: AppIntent {
    static let title: LocalizedStringResource = "Get Weather"
    static let description = IntentDescription(
        "Get the current weather and forecast for a location",
        categoryName: "Tools"
    )

    @Parameter(title: "Location", description: "City or location name (uses current location if empty)")
    var location: String?

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var argsDict: [String: String] = [:]
        if let location { argsDict["location"] = location }
        let data = try JSONSerialization.data(withJSONObject: argsDict)
        let args = String(data: data, encoding: .utf8) ?? "{}"
        let result = try await ToolRegistry.shared.execute(name: "weather", arguments: args)
        return .result(value: result)
    }
}

// MARK: - Get Calendar Events

@available(iOS 16.0, macOS 13.0, *)
struct GetCalendarEventsShortcut: AppIntent {
    static let title: LocalizedStringResource = "Get Calendar Events"
    static let description = IntentDescription(
        "List upcoming calendar events for today or a specific date",
        categoryName: "Tools"
    )

    @Parameter(title: "Action", default: "list")
    var action: String

    @Parameter(title: "Date", description: "Date to check (today if empty)")
    var date: String?

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        var argsDict: [String: String] = ["action": action]
        if let date { argsDict["date"] = date }
        let data = try JSONSerialization.data(withJSONObject: argsDict)
        let args = String(data: data, encoding: .utf8) ?? "{\"action\":\"list\"}"
        let result = try await ToolRegistry.shared.execute(name: "calendar", arguments: args)
        return .result(value: result)
    }
}

// MARK: - Create Reminder

@available(iOS 16.0, macOS 13.0, *)
struct CreateReminderShortcut: AppIntent {
    static let title: LocalizedStringResource = "Create Reminder"
    static let description = IntentDescription(
        "Create a new reminder in Reminders",
        categoryName: "Tools"
    )

    @Parameter(title: "Title")
    var title: String

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let argsDict: [String: String] = ["action": "create", "title": title]
        let data = try JSONSerialization.data(withJSONObject: argsDict)
        let args = String(data: data, encoding: .utf8) ?? "{\"action\":\"create\"}"
        let result = try await ToolRegistry.shared.execute(name: "reminders", arguments: args)
        return .result(value: result)
    }
}

// MARK: - Search Contacts

@available(iOS 16.0, macOS 13.0, *)
struct SearchContactsShortcut: AppIntent {
    static let title: LocalizedStringResource = "Search Contacts"
    static let description = IntentDescription(
        "Search your contacts by name",
        categoryName: "Tools"
    )

    @Parameter(title: "Name")
    var query: String

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let argsDict: [String: String] = ["query": query]
        let data = try JSONSerialization.data(withJSONObject: argsDict)
        let args = String(data: data, encoding: .utf8) ?? "{}"
        let result = try await ToolRegistry.shared.execute(name: "contacts", arguments: args)
        return .result(value: result)
    }
}

// MARK: - Calculate

@available(iOS 16.0, macOS 13.0, *)
struct CalculateShortcut: AppIntent {
    static let title: LocalizedStringResource = "Calculate"
    static let description = IntentDescription(
        "Evaluate a math expression",
        categoryName: "Tools"
    )

    @Parameter(title: "Expression", description: "e.g., 20% of 85, or 15 + 27")
    var expression: String

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let argsDict: [String: String] = ["expression": expression]
        let data = try JSONSerialization.data(withJSONObject: argsDict)
        let args = String(data: data, encoding: .utf8) ?? "{}"
        let result = try await ToolRegistry.shared.execute(name: "calculator", arguments: args)
        return .result(value: result)
    }
}

// MARK: - Fetch Web Content

@available(iOS 16.0, macOS 13.0, *)
struct FetchWebContentShortcut: AppIntent {
    static let title: LocalizedStringResource = "Fetch Web Content"
    static let description = IntentDescription(
        "Fetch and summarize content from a URL",
        categoryName: "Tools"
    )

    @Parameter(title: "URL")
    var url: String

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let argsDict: [String: String] = ["url": url]
        let data = try JSONSerialization.data(withJSONObject: argsDict)
        let args = String(data: data, encoding: .utf8) ?? "{}"
        let result = try await ToolRegistry.shared.execute(name: "web_fetch", arguments: args)
        return .result(value: result)
    }
}

// MARK: - Save to Memory

@available(iOS 16.0, macOS 13.0, *)
struct SaveToMemoryShortcut: AppIntent {
    static let title: LocalizedStringResource = "Save to Memory"
    static let description = IntentDescription(
        "Save a fact or preference to Clarissa's long-term memory",
        categoryName: "Tools"
    )

    @Parameter(title: "Content", description: "What to remember")
    var content: String

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let argsDict: [String: String] = ["content": content]
        let data = try JSONSerialization.data(withJSONObject: argsDict)
        let args = String(data: data, encoding: .utf8) ?? "{}"
        let result = try await ToolRegistry.shared.execute(name: "remember", arguments: args)
        return .result(value: result, dialog: "Saved to memory.")
    }
}

// MARK: - Get Current Location

@available(iOS 16.0, macOS 13.0, *)
struct GetLocationShortcut: AppIntent {
    static let title: LocalizedStringResource = "Get Current Location"
    static let description = IntentDescription(
        "Get the device's current location",
        categoryName: "Tools"
    )

    static let openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try await ToolRegistry.shared.execute(name: "location", arguments: "{}")
        return .result(value: result)
    }
}

// MARK: - Run Tool Chain

@available(iOS 16.0, macOS 13.0, *)
struct RunToolChainShortcut: AppIntent {
    static let title: LocalizedStringResource = "Run Tool Chain"
    static let description = IntentDescription(
        "Execute a saved multi-step tool chain workflow",
        categoryName: "Automation"
    )

    @Parameter(title: "Chain ID", description: "ID of the tool chain to run")
    var chainId: String

    @Parameter(title: "Input", description: "Optional input for the chain")
    var userInput: String?

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let chains = await ToolChain.allChains()
        guard let chain = chains.first(where: { $0.id == chainId }) else {
            return .result(value: "Chain '\(chainId)' not found.")
        }

        let executor = ToolChainExecutor()
        let result = try await executor.execute(chain: chain, userInput: userInput)
        return .result(value: result.synthesisContext)
    }
}

