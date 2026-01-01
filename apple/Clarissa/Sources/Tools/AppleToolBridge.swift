import Foundation
import os.log
#if canImport(FoundationModels)
import FoundationModels

// MARK: - Apple Tool Bridge
//
// IMPORTANT: Actor Isolation Notes for Foundation Models Tool Integration
//
// Apple's Foundation Models framework calls Tool.call() from a BACKGROUND THREAD
// (specifically from ToolCallCoordinator.runLoop). This creates a critical actor
// isolation issue because our underlying tools may access @MainActor isolated code:
//
// - CLLocationManager (WeatherTool, LocationTool) requires MainActor
// - ToolRegistry is @MainActor isolated
// - SpeechRecognizer and voice components are @MainActor isolated
// - UI updates must happen on MainActor
//
// The solution is to wrap all tool executions in safeToolExecution() which:
// 1. Properly hops to the MainActor before executing the underlying tool
// 2. Catches any errors and returns them as JSON instead of throwing
//    (Foundation Models throws decodingFailure when tools throw errors)
//
// If you add a new Apple Tool Bridge struct:
// 1. Always use `await safeToolExecution(name) { ... }` in the call() method
// 2. Capture the underlyingTool in a local variable before the closure
// 3. Test with actual Foundation Models to verify no crashes
//
// Reference: Thread 4 crash in _dispatch_assert_queue_fail when this is violated

// MARK: - Debug Logging

/// Logger for tool debugging
/// Community insight: Use DEBUG logging to debug tool invocation issues
private let toolLogger = Logger(subsystem: "dev.rye.Clarissa", category: "AppleTools")

// MARK: - MainActor Helper

/// Execute an async closure on the MainActor
/// Foundation Models calls tools from a background thread, but our underlying tools
/// may access @MainActor isolated code (CLLocationManager, Keychain, etc.)
/// This helper ensures proper actor isolation to prevent Swift concurrency crashes
@available(iOS 26.0, macOS 26.0, *)
private func executeOnMainActor<T: Sendable>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
    try await Task { @MainActor in
        try await operation()
    }.value
}

/// Safely execute a tool operation and return error JSON instead of throwing
/// Foundation Models may throw decodingFailure when tools throw errors,
/// so we catch errors and return them as structured JSON responses instead.
@available(iOS 26.0, macOS 26.0, *)
private func safeToolExecution(_ toolName: String, _ operation: @escaping @MainActor () async throws -> String) async -> String {
    do {
        return try await Task { @MainActor in
            try await operation()
        }.value
    } catch {
        // Log the error for debugging
        toolLogger.error("Tool '\(toolName)' failed: \(error.localizedDescription)")

        // Return error as JSON so the model can inform the user
        let errorMessage = getUserFriendlyError(error)
        return """
        {"error": true, "message": "\(errorMessage.replacingOccurrences(of: "\"", with: "\\\""))"}
        """
    }
}

/// Convert error to user-friendly message for tool responses
private func getUserFriendlyError(_ error: Error) -> String {
    if let toolError = error as? ToolError {
        switch toolError {
        case .notAvailable(let reason):
            return "Not available: \(reason)"
        case .permissionDenied(let permission):
            return "Permission needed for \(permission). Please check Settings."
        case .invalidArguments:
            return "Invalid request. Please try rephrasing."
        case .executionFailed(let reason):
            return reason
        }
    }

    let desc = error.localizedDescription.lowercased()
    if desc.contains("network") || desc.contains("internet") {
        return "No internet connection. Please check your connection."
    }
    if desc.contains("permission") || desc.contains("denied") {
        return "Permission denied. Please check app permissions in Settings."
    }
    if desc.contains("location") {
        return "Could not access location. Please enable location services."
    }

    return "Unable to complete request: \(error.localizedDescription)"
}

// MARK: - Native Tool Usage Tracker

/// Tracks tool usage for Foundation Models native tool calls
/// Since Foundation Models handles tools opaquely, we track usage here
/// to report accurate context stats in the UI
@MainActor
final class NativeToolUsageTracker {
    static let shared = NativeToolUsageTracker()

    private(set) var totalToolTokens: Int = 0
    private(set) var toolCallCount: Int = 0

    private init() {}

    /// Record a tool call with its arguments and result
    func recordToolCall(name: String, arguments: String, result: String) {
        toolCallCount += 1
        // Estimate tokens: tool name + arguments + result
        // Using similar estimation as TokenBudget.estimate
        let argTokens = max(1, arguments.count / 4)
        let resultTokens = max(1, result.count / 4)
        let nameTokens = max(1, name.count / 4)
        totalToolTokens += argTokens + resultTokens + nameTokens
    }

    /// Reset tracking (call when starting a new conversation)
    func reset() {
        totalToolTokens = 0
        toolCallCount = 0
    }
}

/// Log tool call for debugging
@inline(__always)
private func logToolCall(_ name: String, _ arguments: Any) {
    #if DEBUG
    toolLogger.debug("Tool '\(name)' called with: \(String(describing: arguments))")
    #endif
}

/// Log tool result for debugging and track usage
@inline(__always)
private func logToolResult(_ name: String, arguments: String, _ result: String) {
    #if DEBUG
    let truncated = result.count > 200 ? String(result.prefix(200)) + "..." : result
    toolLogger.debug("Tool '\(name)' returned: \(truncated)")
    #endif

    // Track tool usage for context stats (on MainActor)
    Task { @MainActor in
        NativeToolUsageTracker.shared.recordToolCall(name: name, arguments: arguments, result: result)
    }
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
        let typedArgs = WeatherToolArgs(
            location: arguments.location,
            latitude: arguments.latitude,
            longitude: arguments.longitude,
            forecast: arguments.forecast
        )
        let jsonData = try JSONEncoder().encode(typedArgs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let tool = underlyingTool
        let result = await safeToolExecution(name) {
            return try await tool.execute(arguments: jsonString)
        }
        logToolResult(name, arguments: jsonString, result)
        return result
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
        let tool = underlyingTool
        let result = await safeToolExecution(name) {
            return try await tool.execute(arguments: jsonString)
        }
        logToolResult(name, arguments: jsonString, result)
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
        let tool = underlyingTool
        let result = await safeToolExecution(name) {
            return try await tool.execute(arguments: jsonString)
        }
        logToolResult(name, arguments: jsonString, result)
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
        let tool = underlyingTool
        let result = await safeToolExecution(name) {
            return try await tool.execute(arguments: jsonString)
        }
        logToolResult(name, arguments: jsonString, result)
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
        let tool = underlyingTool
        let result = await safeToolExecution(name) {
            return try await tool.execute(arguments: jsonString)
        }
        logToolResult(name, arguments: jsonString, result)
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
        let tool = underlyingTool
        let result = await safeToolExecution(name) {
            return try await tool.execute(arguments: jsonString)
        }
        logToolResult(name, arguments: jsonString, result)
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
        let tool = underlyingTool
        let result = await safeToolExecution(name) {
            return try await tool.execute(arguments: jsonString)
        }
        logToolResult(name, arguments: jsonString, result)
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
        let tool = underlyingTool
        let result = await safeToolExecution(name) {
            return try await tool.execute(arguments: jsonString)
        }
        logToolResult(name, arguments: jsonString, result)
        return result
    }
}

// MARK: - Image Analysis Tool

/// Typed arguments for image analysis tool
struct ImageAnalysisToolArgs: Codable, Sendable {
    var action: String
    var imageBase64: String?
    var imageURL: String?
    var pdfBase64: String?
    var pdfURL: String?
    var pageRange: String?
}

/// Apple Foundation Models Tool for image and PDF analysis using Vision and PDFKit frameworks
@available(iOS 26.0, macOS 26.0, *)
struct AppleImageAnalysisTool: Tool {
    let name = "image_analysis"
    // Enhanced description with specific triggers for images and PDFs
    let description = "Analyze images or PDFs for text, objects, faces, or documents. TRIGGERS: 'read text from image', 'what's in this photo', 'OCR', 'scan', 'summarize PDF', 'read PDF', 'extract text from PDF'. Image actions: ocr, classify, detect_faces, detect_document. PDF actions: pdf_extract_text, pdf_ocr, pdf_page_count."

    private let underlyingTool: ImageAnalysisTool

    @Generable(description: "Image and PDF analysis parameters")
    struct Arguments {
        @Guide(description: "Analysis type: 'ocr' for image text, 'classify' for objects, 'detect_faces' for faces, 'detect_document' for boundaries, 'pdf_extract_text' for searchable PDFs, 'pdf_ocr' for scanned PDFs, 'pdf_page_count' for page count")
        var action: String

        @Guide(description: "Base64-encoded image data (for image actions)")
        var imageBase64: String?

        @Guide(description: "File URL to the image (file:// scheme)")
        var imageURL: String?

        @Guide(description: "Base64-encoded PDF data (for pdf_ actions)")
        var pdfBase64: String?

        @Guide(description: "File URL to the PDF (file:// scheme)")
        var pdfURL: String?

        @Guide(description: "Page range for PDF operations, e.g., '1-5' or '1,3,5' (optional)")
        var pageRange: String?
    }

    init(wrapping tool: ImageAnalysisTool) {
        self.underlyingTool = tool
    }

    func call(arguments: Arguments) async throws -> String {
        logToolCall(name, arguments)
        let typedArgs = ImageAnalysisToolArgs(
            action: arguments.action,
            imageBase64: arguments.imageBase64,
            imageURL: arguments.imageURL,
            pdfBase64: arguments.pdfBase64,
            pdfURL: arguments.pdfURL,
            pageRange: arguments.pageRange
        )
        let jsonData = try JSONEncoder().encode(typedArgs)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        let tool = underlyingTool
        let result = await safeToolExecution(name) {
            return try await tool.execute(arguments: jsonString)
        }
        logToolResult(name, arguments: jsonString, result)
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

