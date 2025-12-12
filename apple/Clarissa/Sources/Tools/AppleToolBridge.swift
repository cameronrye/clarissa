import Foundation
import os.log
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Debug Logging

/// Logger for tool debugging
/// Community insight: Use DEBUG logging to debug tool invocation issues
private let toolLogger = Logger(subsystem: "dev.rye.Clarissa", category: "AppleTools")

/// Log tool call for debugging
@inline(__always)
private func logToolCall(_ name: String, _ arguments: Any) {
    #if DEBUG
    toolLogger.debug("Tool '\(name)' called with: \(String(describing: arguments))")
    #endif
}

/// Log tool result for debugging
@inline(__always)
private func logToolResult(_ name: String, _ result: String) {
    #if DEBUG
    let truncated = result.count > 200 ? String(result.prefix(200)) + "..." : result
    toolLogger.debug("Tool '\(name)' returned: \(truncated)")
    #endif
}

// MARK: - Weather Tool

/// Apple Foundation Models Tool for weather information
@available(iOS 26.0, macOS 26.0, *)
struct AppleWeatherTool: Tool {
    let name = "weather"
    let description = "Get current weather and forecast for a location. Can use location name or coordinates."

    private let underlyingTool: WeatherTool

    @Generable(description: "Weather request parameters")
    struct Arguments {
        @Guide(description: "Location name (e.g., 'San Francisco, CA'). If omitted, uses current location.")
        let location: String?

        @Guide(description: "Latitude coordinate for precise location")
        let latitude: Double?

        @Guide(description: "Longitude coordinate for precise location")
        let longitude: Double?

        @Guide(description: "Include 5-day forecast in the response")
        let forecast: Bool?
    }

    init(wrapping tool: WeatherTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        var dict: [String: Any] = [:]
        if let v = arguments.location { dict["location"] = v }
        if let v = arguments.latitude { dict["latitude"] = v }
        if let v = arguments.longitude { dict["longitude"] = v }
        if let v = arguments.forecast { dict["forecast"] = v }

        let jsonString = dict.toJSONString()
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Calculator Tool

/// Apple Foundation Models Tool for mathematical calculations
@available(iOS 26.0, macOS 26.0, *)
struct AppleCalculatorTool: Tool {
    let name = "calculator"
    let description = "Evaluate mathematical expressions. Supports arithmetic, exponents, parentheses, and functions (sqrt, sin, cos, tan, log, abs, floor, ceil, round, pow) and constants (PI, E)."

    private let underlyingTool: CalculatorTool

    @Generable(description: "Calculator input")
    struct Arguments {
        @Guide(description: "The mathematical expression to evaluate (e.g., '2 + 2', 'sqrt(16)', 'sin(PI/2)')")
        let expression: String
    }

    init(wrapping tool: CalculatorTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let dict: [String: Any] = ["expression": arguments.expression]
        let jsonString = dict.toJSONString()
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Calendar Tool

/// Apple Foundation Models Tool for calendar operations
@available(iOS 26.0, macOS 26.0, *)
struct AppleCalendarTool: Tool {
    let name = "calendar"
    let description = "Create, list, and search calendar events."

    private let underlyingTool: CalendarTool

    @Generable(description: "Calendar operation parameters")
    struct Arguments {
        @Guide(description: "Action to perform: 'create', 'list', or 'search'")
        let action: String

        @Guide(description: "Event title (required for create)")
        let title: String?

        @Guide(description: "Start date/time in ISO 8601 format (e.g., '2024-01-15T10:00:00')")
        let startDate: String?

        @Guide(description: "End date/time in ISO 8601 format")
        let endDate: String?

        @Guide(description: "Event location")
        let location: String?

        @Guide(description: "Event notes or description")
        let notes: String?

        @Guide(description: "Days ahead to list events (default: 7)")
        let daysAhead: Int?

        @Guide(description: "Search query for finding events")
        let query: String?
    }

    init(wrapping tool: CalendarTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        var dict: [String: Any] = ["action": arguments.action]
        if let v = arguments.title { dict["title"] = v }
        if let v = arguments.startDate { dict["startDate"] = v }
        if let v = arguments.endDate { dict["endDate"] = v }
        if let v = arguments.location { dict["location"] = v }
        if let v = arguments.notes { dict["notes"] = v }
        if let v = arguments.daysAhead { dict["daysAhead"] = v }
        if let v = arguments.query { dict["query"] = v }

        let jsonString = dict.toJSONString()
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Contacts Tool

/// Apple Foundation Models Tool for contacts operations
@available(iOS 26.0, macOS 26.0, *)
struct AppleContactsTool: Tool {
    let name = "contacts"
    let description = "Search and retrieve contact information."

    private let underlyingTool: ContactsTool

    @Generable(description: "Contacts operation parameters")
    struct Arguments {
        @Guide(description: "Action to perform: 'search' or 'get'")
        let action: String

        @Guide(description: "Search query - name, phone, or email")
        let query: String?

        @Guide(description: "Contact identifier (for get action)")
        let contactId: String?

        @Guide(description: "Maximum number of results to return (default: 10)")
        let limit: Int?
    }

    init(wrapping tool: ContactsTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        var dict: [String: Any] = ["action": arguments.action]
        if let v = arguments.query { dict["query"] = v }
        if let v = arguments.contactId { dict["contactId"] = v }
        if let v = arguments.limit { dict["limit"] = v }

        let jsonString = dict.toJSONString()
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}


// MARK: - Reminders Tool

/// Apple Foundation Models Tool for reminders operations
@available(iOS 26.0, macOS 26.0, *)
struct AppleRemindersTool: Tool {
    let name = "reminders"
    let description = "Create, list, and complete reminders."

    private let underlyingTool: RemindersTool

    @Generable(description: "Reminders operation parameters")
    struct Arguments {
        @Guide(description: "Action to perform: 'list', 'create', or 'complete'")
        let action: String

        @Guide(description: "Title for new reminder (required for create)")
        let title: String?

        @Guide(description: "Notes for the reminder")
        let notes: String?

        @Guide(description: "Due date in ISO8601 format (e.g., '2024-01-15T10:00:00')")
        let dueDate: String?

        @Guide(description: "Priority: 0=none, 1=high, 5=medium, 9=low")
        let priority: Int?

        @Guide(description: "Reminder ID (required for complete action)")
        let reminderId: String?

        @Guide(description: "Name of reminder list to use")
        let listName: String?
    }

    init(wrapping tool: RemindersTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        var dict: [String: Any] = ["action": arguments.action]
        if let v = arguments.title { dict["title"] = v }
        if let v = arguments.notes { dict["notes"] = v }
        if let v = arguments.dueDate { dict["dueDate"] = v }
        if let v = arguments.priority { dict["priority"] = v }
        if let v = arguments.reminderId { dict["reminderId"] = v }
        if let v = arguments.listName { dict["listName"] = v }

        let jsonString = dict.toJSONString()
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Location Tool

/// Apple Foundation Models Tool for location information
@available(iOS 26.0, macOS 26.0, *)
struct AppleLocationTool: Tool {
    let name = "location"
    let description = "Get the user's current location."

    private let underlyingTool: LocationTool

    @Generable(description: "Location request parameters")
    struct Arguments {
        @Guide(description: "Whether to include address details in the response")
        let includeAddress: Bool?
    }

    init(wrapping tool: LocationTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        var dict: [String: Any] = [:]
        if let v = arguments.includeAddress { dict["includeAddress"] = v }

        let jsonString = dict.toJSONString()
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Web Fetch Tool

/// Apple Foundation Models Tool for fetching web content
@available(iOS 26.0, macOS 26.0, *)
struct AppleWebFetchTool: Tool {
    let name = "web_fetch"
    let description = "Fetch content from a URL. Returns text content extracted from the webpage."

    private let underlyingTool: WebFetchTool

    @Generable(description: "Web fetch parameters")
    struct Arguments {
        @Guide(description: "The URL to fetch content from")
        let url: String

        @Guide(description: "Response format: 'text', 'json', or 'html' (default: text)")
        let format: String?

        @Guide(description: "Maximum content length to return")
        let maxLength: Int?
    }

    init(wrapping tool: WebFetchTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        var dict: [String: Any] = ["url": arguments.url]
        if let v = arguments.format { dict["format"] = v }
        if let v = arguments.maxLength { dict["maxLength"] = v }

        let jsonString = dict.toJSONString()
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Remember Tool

/// Apple Foundation Models Tool for storing memories
@available(iOS 26.0, macOS 26.0, *)
struct AppleRememberTool: Tool {
    let name = "remember"
    let description = "Store important information for future conversations. Use this to remember user preferences, facts, or context."

    private let underlyingTool: RememberTool

    @Generable(description: "Memory storage parameters")
    struct Arguments {
        @Guide(description: "The content to remember for future conversations")
        let content: String
    }

    init(wrapping tool: RememberTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let dict: [String: Any] = ["content": arguments.content]
        let jsonString = dict.toJSONString()
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Helper Extension

/// Helper to convert dictionary to JSON string
private extension Dictionary where Key == String, Value == Any {
    func toJSONString() -> String {
        if let data = try? JSONSerialization.data(withJSONObject: self),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

#endif

