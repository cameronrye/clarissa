import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Registry for all available tools
@MainActor
public final class ToolRegistry {
    public static let shared = ToolRegistry()

    private var tools: [String: any ClarissaTool] = [:]

    private init() {
        // Register core tools
        register(CalendarTool())
        register(ContactsTool())
        register(CalculatorTool())
        register(RememberTool())

        // Register extended tools
        register(WebFetchTool())
        register(RemindersTool())
        register(LocationTool())

        // Register weather tool (iOS 16+)
        if #available(iOS 16.0, macOS 13.0, *) {
            register(WeatherTool())
        }

        // Register image analysis tool (Vision framework)
        register(ImageAnalysisTool())
    }
    
    /// Register a new tool
    func register(_ tool: any ClarissaTool) {
        tools[tool.name] = tool
    }
    
    /// Get a tool by name
    func get(_ name: String) -> (any ClarissaTool)? {
        tools[name]
    }
    
    /// Get all tool names
    func getToolNames() -> [String] {
        Array(tools.keys).sorted()
    }
    
    /// Get tool definitions for the LLM (respects enabled tools from ToolSettings)
    func getDefinitions() -> [ToolDefinition] {
        let enabledNames = ToolSettings.shared.enabledToolNames
        return tools.values
            .filter { enabledNames.contains($0.name) }
            .sorted { $0.priority < $1.priority }
            .map { $0.toDefinition() }
    }

    /// Get limited number of tools (for providers with tool limits)
    func getDefinitionsLimited(_ maxTools: Int) -> [ToolDefinition] {
        Array(getDefinitions().prefix(maxTools))
    }

    /// Get all tool definitions regardless of enabled state (for settings display)
    func getAllDefinitions() -> [ToolDefinition] {
        tools.values
            .sorted { $0.priority < $1.priority }
            .map { $0.toDefinition() }
    }

    /// Get descriptions of disabled tools for system prompt
    /// Returns a list of (displayName, capability) tuples for disabled tools
    func getDisabledToolDescriptions() -> [(name: String, capability: String)] {
        let enabledNames = ToolSettings.shared.enabledToolNames
        let disabledTools = ToolSettings.shared.allTools.filter { !enabledNames.contains($0.id) }

        // Map tool IDs to user-friendly capability descriptions
        return disabledTools.compactMap { toolInfo -> (name: String, capability: String)? in
            let capability: String
            switch toolInfo.id {
            case "remember":
                capability = "remember information across conversations"
            case "weather":
                capability = "get weather forecasts"
            case "calendar":
                capability = "manage calendar events"
            case "contacts":
                capability = "search contacts"
            case "reminders":
                capability = "create reminders and to-dos"
            case "calculator":
                capability = "perform math calculations"
            case "location":
                capability = "get current location"
            case "web_fetch":
                capability = "fetch web content"
            case "image_analysis":
                capability = "analyze images for text, objects, and faces"
            default:
                capability = toolInfo.description.lowercased()
            }
            return (name: toolInfo.name, capability: capability)
        }
    }

    /// Execute a tool by name
    /// Tool execution happens off the main thread to prevent UI freezes
    func execute(name: String, arguments: String) async throws -> String {
        guard let tool = tools[name] else {
            throw ToolError.notAvailable("Tool '\(name)' not found")
        }

        // Execute tool off the main actor to prevent UI blocking
        return try await Task.detached(priority: .userInitiated) {
            try await tool.execute(arguments: arguments)
        }.value
    }

    #if canImport(FoundationModels)
    /// Get tools as Apple Foundation Models Tool protocol instances
    /// This enables native tool calling with Apple Intelligence
    /// Uses properly typed tool bridges with @Generable arguments for each tool
    /// Only returns tools that are enabled in ToolSettings
    @available(iOS 26.0, macOS 26.0, *)
    func getAppleTools() -> [any Tool] {
        var appleTools: [any Tool] = []
        let enabledNames = ToolSettings.shared.enabledToolNames

        // Create typed Apple tools for each enabled ClarissaTool
        // Order by priority (core tools first)
        let sortedTools = tools.values
            .filter { enabledNames.contains($0.name) }
            .sorted { $0.priority < $1.priority }

        for tool in sortedTools {
            if let appleTool = createAppleTool(for: tool) {
                appleTools.append(appleTool)
            }
        }

        return appleTools
    }

    /// Get Apple tools limited to Foundation Models max (already filtered by enabled)
    @available(iOS 26.0, macOS 26.0, *)
    func getAppleToolsLimited(_ maxTools: Int) -> [any Tool] {
        Array(getAppleTools().prefix(maxTools))
    }

    /// Create a properly typed Apple Tool for a ClarissaTool
    @available(iOS 26.0, macOS 26.0, *)
    private func createAppleTool(for tool: any ClarissaTool) -> (any Tool)? {
        switch tool.name {
        case "weather":
            guard let weatherTool = tool as? WeatherTool else { return nil }
            return AppleWeatherTool(wrapping: weatherTool)
        case "calculator":
            guard let calcTool = tool as? CalculatorTool else { return nil }
            return AppleCalculatorTool(wrapping: calcTool)
        case "calendar":
            guard let calTool = tool as? CalendarTool else { return nil }
            return AppleCalendarTool(wrapping: calTool)
        case "contacts":
            guard let contactsTool = tool as? ContactsTool else { return nil }
            return AppleContactsTool(wrapping: contactsTool)
        case "reminders":
            guard let remindersTool = tool as? RemindersTool else { return nil }
            return AppleRemindersTool(wrapping: remindersTool)
        case "location":
            guard let locationTool = tool as? LocationTool else { return nil }
            return AppleLocationTool(wrapping: locationTool)
        case "web_fetch":
            guard let webTool = tool as? WebFetchTool else { return nil }
            return AppleWebFetchTool(wrapping: webTool)
        case "remember":
            guard let rememberTool = tool as? RememberTool else { return nil }
            return AppleRememberTool(wrapping: rememberTool)
        case "image_analysis":
            guard let imageTool = tool as? ImageAnalysisTool else { return nil }
            return AppleImageAnalysisTool(wrapping: imageTool)
        default:
            // Unknown tool - skip it
            return nil
        }
    }
    #endif
}

