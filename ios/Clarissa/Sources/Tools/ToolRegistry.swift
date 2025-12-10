import Foundation

/// Registry for all available tools
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()
    
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
    
    /// Get tool definitions for the LLM
    func getDefinitions() -> [ToolDefinition] {
        tools.values
            .sorted { $0.priority < $1.priority }
            .map { $0.toDefinition() }
    }
    
    /// Get limited number of tools (for providers with tool limits)
    func getDefinitionsLimited(_ maxTools: Int) -> [ToolDefinition] {
        Array(getDefinitions().prefix(maxTools))
    }
    
    /// Check if a tool requires confirmation
    func requiresConfirmation(_ name: String) -> Bool {
        tools[name]?.requiresConfirmation ?? false
    }
    
    /// Execute a tool by name
    func execute(name: String, arguments: String) async throws -> String {
        guard let tool = tools[name] else {
            throw ToolError.notAvailable("Tool '\(name)' not found")
        }
        
        return try await tool.execute(arguments: arguments)
    }
}

