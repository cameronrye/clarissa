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

/// Typed arguments for weather tool - Codable for efficient serialization
struct WeatherToolArgs: Codable, Sendable {
    var location: String?
    var latitude: Double?
    var longitude: Double?
    var forecast: Bool?
}

/// Apple Foundation Models Tool for weather information
@available(iOS 26.0, macOS 26.0, *)
struct AppleWeatherTool: Tool {
    let name = "weather"
    // Enhanced description with specific triggers for better model selection
    let description = "Get current weather and forecast. TRIGGERS: 'weather', 'temperature', 'hot', 'cold', 'rain', 'sunny', 'forecast'. No params = current location. Returns: conditions, temp, humidity."

    private let underlyingTool: WeatherTool

    @Generable(description: "Weather request parameters")
    struct Arguments {
        @Guide(description: "Location name (e.g., 'San Francisco, CA'). If omitted, uses current location.")
        var location: String?

        @Guide(description: "Latitude coordinate for precise location")
        var latitude: Double?

        @Guide(description: "Longitude coordinate for precise location")
        var longitude: Double?

        @Guide(description: "Include 5-day forecast in the response")
        var forecast: Bool?
    }

    init(wrapping tool: WeatherTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        // Direct conversion without JSON round-trip
        let typedArgs = WeatherToolArgs(
            location: arguments.location,
            latitude: arguments.latitude,
            longitude: arguments.longitude,
            forecast: arguments.forecast
        )
        let result = try await executeWithTypedArgs(typedArgs)
        logToolResult(name, result)
        return result
    }

    /// Execute with typed arguments using Codable serialization
    private func executeWithTypedArgs(_ args: WeatherToolArgs) async throws -> String {
        let jsonData = try JSONEncoder().encode(args)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        return try await underlyingTool.execute(arguments: jsonString)
    }
}

// MARK: - Calculator Tool

/// Typed arguments for calculator tool
struct CalculatorToolArgs: Codable, Sendable {
    var expression: String
}

/// Apple Foundation Models Tool for mathematical calculations
@available(iOS 26.0, macOS 26.0, *)
struct AppleCalculatorTool: Tool {
    let name = "calculator"
    // Enhanced description with specific triggers and examples
    let description = "Compute math expressions. TRIGGERS: 'calculate', 'what is X+Y', 'percent', 'tip', 'convert', 'how much'. Example: '47.50 * 0.18' for 18% tip. Returns: numeric result."

    private let underlyingTool: CalculatorTool

    @Generable(description: "Calculator input")
    struct Arguments {
        @Guide(description: "The mathematical expression to evaluate (e.g., '2 + 2', 'sqrt(16)', 'sin(PI/2)')")
        var expression: String
    }

    init(wrapping tool: CalculatorTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let typedArgs = CalculatorToolArgs(expression: arguments.expression)
        let jsonData = try JSONEncoder().encode(typedArgs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Calendar Tool

/// Typed arguments for calendar tool
struct CalendarToolArgs: Codable, Sendable {
    var action: String
    var title: String?
    var startDate: String?
    var endDate: String?
    var location: String?
    var notes: String?
    var daysAhead: Int?
    var query: String?
}

/// Apple Foundation Models Tool for calendar operations
@available(iOS 26.0, macOS 26.0, *)
struct AppleCalendarTool: Tool {
    let name = "calendar"
    // Enhanced description with specific triggers
    let description = "Create or list calendar events. TRIGGERS: 'schedule', 'meeting', 'appointment', 'calendar', 'what's on'. Actions: create (title+startDate required), list (daysAhead), search (query)."

    private let underlyingTool: CalendarTool

    @Generable(description: "Calendar operation parameters")
    struct Arguments {
        @Guide(description: "Action to perform: 'create', 'list', or 'search'")
        var action: String

        @Guide(description: "Event title (required for create)")
        var title: String?

        @Guide(description: "Start date/time in ISO 8601 format (e.g., '2024-01-15T10:00:00')")
        var startDate: String?

        @Guide(description: "End date/time in ISO 8601 format")
        var endDate: String?

        @Guide(description: "Event location")
        var location: String?

        @Guide(description: "Event notes or description")
        var notes: String?

        @Guide(description: "Days ahead to list events (default: 7)")
        var daysAhead: Int?

        @Guide(description: "Search query for finding events")
        var query: String?
    }

    init(wrapping tool: CalendarTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let typedArgs = CalendarToolArgs(
            action: arguments.action,
            title: arguments.title,
            startDate: arguments.startDate,
            endDate: arguments.endDate,
            location: arguments.location,
            notes: arguments.notes,
            daysAhead: arguments.daysAhead,
            query: arguments.query
        )
        let jsonData = try JSONEncoder().encode(typedArgs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Contacts Tool

/// Typed arguments for contacts tool
struct ContactsToolArgs: Codable, Sendable {
    var action: String
    var query: String?
    var contactId: String?
    var limit: Int?
}

/// Apple Foundation Models Tool for contacts operations
@available(iOS 26.0, macOS 26.0, *)
struct AppleContactsTool: Tool {
    let name = "contacts"
    // Enhanced description with specific triggers
    let description = "Look up contact information. TRIGGERS: 'phone number', 'email', 'contact', 'call', 'text', 'message'. Actions: search (query by name). Returns: name, phone, email."

    private let underlyingTool: ContactsTool

    @Generable(description: "Contacts operation parameters")
    struct Arguments {
        @Guide(description: "Action to perform: 'search' or 'get'")
        var action: String

        @Guide(description: "Search query - name, phone, or email")
        var query: String?

        @Guide(description: "Contact identifier (for get action)")
        var contactId: String?

        @Guide(description: "Maximum number of results to return (default: 10)")
        var limit: Int?
    }

    init(wrapping tool: ContactsTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let typedArgs = ContactsToolArgs(
            action: arguments.action,
            query: arguments.query,
            contactId: arguments.contactId,
            limit: arguments.limit
        )
        let jsonData = try JSONEncoder().encode(typedArgs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}


// MARK: - Reminders Tool

/// Typed arguments for reminders tool
struct RemindersToolArgs: Codable, Sendable {
    var action: String
    var title: String?
    var notes: String?
    var dueDate: String?
    var priority: Int?
    var reminderId: String?
    var listName: String?
}

/// Apple Foundation Models Tool for reminders operations
@available(iOS 26.0, macOS 26.0, *)
struct AppleRemindersTool: Tool {
    let name = "reminders"
    // Enhanced description with specific triggers
    let description = "Create or list reminders/tasks. TRIGGERS: 'remind me', 'reminder', 'task', 'to-do', 'don't forget'. Actions: create (title required), list, complete. Returns: reminder details."

    private let underlyingTool: RemindersTool

    @Generable(description: "Reminders operation parameters")
    struct Arguments {
        @Guide(description: "Action to perform: 'list', 'create', or 'complete'")
        var action: String

        @Guide(description: "Title for new reminder (required for create)")
        var title: String?

        @Guide(description: "Notes for the reminder")
        var notes: String?

        @Guide(description: "Due date in ISO8601 format (e.g., '2024-01-15T10:00:00')")
        var dueDate: String?

        @Guide(description: "Priority: 0=none, 1=high, 5=medium, 9=low")
        var priority: Int?

        @Guide(description: "Reminder ID (required for complete action)")
        var reminderId: String?

        @Guide(description: "Name of reminder list to use")
        var listName: String?
    }

    init(wrapping tool: RemindersTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let typedArgs = RemindersToolArgs(
            action: arguments.action,
            title: arguments.title,
            notes: arguments.notes,
            dueDate: arguments.dueDate,
            priority: arguments.priority,
            reminderId: arguments.reminderId,
            listName: arguments.listName
        )
        let jsonData = try JSONEncoder().encode(typedArgs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Location Tool

/// Typed arguments for location tool
struct LocationToolArgs: Codable, Sendable {
    var includeAddress: Bool?
}

/// Apple Foundation Models Tool for location information
@available(iOS 26.0, macOS 26.0, *)
struct AppleLocationTool: Tool {
    let name = "location"
    // Enhanced description with specific triggers
    let description = "Get current device location. TRIGGERS: 'where am I', 'my location', 'current location', 'nearby'. Returns: city, address, coordinates."

    private let underlyingTool: LocationTool

    @Generable(description: "Location request parameters")
    struct Arguments {
        @Guide(description: "Whether to include address details in the response")
        var includeAddress: Bool?
    }

    init(wrapping tool: LocationTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let typedArgs = LocationToolArgs(includeAddress: arguments.includeAddress)
        let jsonData = try JSONEncoder().encode(typedArgs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Web Fetch Tool

/// Typed arguments for web fetch tool
struct WebFetchToolArgs: Codable, Sendable {
    var url: String
    var format: String?
    var maxLength: Int?
}

/// Apple Foundation Models Tool for fetching web content
@available(iOS 26.0, macOS 26.0, *)
struct AppleWebFetchTool: Tool {
    let name = "web_fetch"
    // Enhanced description with specific triggers
    let description = "Fetch and read webpage content. TRIGGERS: URL provided, 'read this page', 'fetch', 'get content from'. Returns: extracted text content from the URL."

    private let underlyingTool: WebFetchTool

    @Generable(description: "Web fetch parameters")
    struct Arguments {
        @Guide(description: "The URL to fetch content from")
        var url: String

        @Guide(description: "Response format: 'text', 'json', or 'html' (default: text)")
        var format: String?

        @Guide(description: "Maximum content length to return")
        var maxLength: Int?
    }

    init(wrapping tool: WebFetchTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let typedArgs = WebFetchToolArgs(
            url: arguments.url,
            format: arguments.format,
            maxLength: arguments.maxLength
        )
        let jsonData = try JSONEncoder().encode(typedArgs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let result = try await underlyingTool.execute(arguments: jsonString)
        logToolResult(name, result)
        return result
    }
}

// MARK: - Remember Tool

/// Typed arguments for remember tool
struct RememberToolArgs: Codable, Sendable {
    var content: String
}

/// Apple Foundation Models Tool for storing memories
@available(iOS 26.0, macOS 26.0, *)
struct AppleRememberTool: Tool {
    let name = "remember"
    // Enhanced description with specific triggers
    let description = "Save user preferences for future conversations. TRIGGERS: 'remember that', 'remember I', 'my preference is', 'I like'. Returns: confirmation that info was saved."

    private let underlyingTool: RememberTool

    @Generable(description: "Memory storage parameters")
    struct Arguments {
        @Guide(description: "The content to remember for future conversations")
        var content: String
    }

    init(wrapping tool: RememberTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let typedArgs = RememberToolArgs(content: arguments.content)
        let jsonData = try JSONEncoder().encode(typedArgs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
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

