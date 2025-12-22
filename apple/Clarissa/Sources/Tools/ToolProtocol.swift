import Foundation

/// Priority levels for tools - higher priority tools are included first
enum ToolPriority: Int, Comparable {
    case core = 1      // Essential tools always included
    case important = 2 // Commonly used tools
    case extended = 3  // Specialized tools

    static func < (lhs: ToolPriority, rhs: ToolPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Base protocol for all tools
protocol ClarissaTool: Sendable {
    /// Tool name (used in LLM calls)
    var name: String { get }

    /// Tool description for the LLM
    var description: String { get }

    /// Tool priority for selection
    var priority: ToolPriority { get }

    /// JSON Schema for parameters
    var parametersSchema: [String: Any] { get }

    /// Execute the tool with the given JSON arguments
    func execute(arguments: String) async throws -> String
}

/// Default implementations
extension ClarissaTool {
    var priority: ToolPriority { .extended }
}

/// Convert a tool to a definition for the LLM
extension ClarissaTool {
    func toDefinition() -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            parameters: parametersSchema
        )
    }
}

// MARK: - Typed Arguments Support

/// Protocol for typed tool arguments that can be parsed from JSON or constructed directly
/// This enables direct argument passing from Apple Foundation Models without JSON round-trips
protocol TypedToolArguments: Codable, Sendable {
    /// Create arguments from a JSON string (for OpenRouter/manual tool calls)
    init(jsonString: String) throws
}

extension TypedToolArguments {
    init(jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw ToolError.invalidArguments("Invalid JSON encoding")
        }
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}

/// Extended protocol for tools that support typed arguments
/// Tools conforming to this can receive arguments directly without JSON serialization
protocol TypedClarissaTool: ClarissaTool {
    associatedtype Arguments: TypedToolArguments

    /// Execute with typed arguments (preferred for Apple Foundation Models)
    func execute(typedArguments: Arguments) async throws -> String
}

/// Default implementation bridges typed execution to JSON-based execution
extension TypedClarissaTool {
    func execute(arguments: String) async throws -> String {
        let typedArgs = try Arguments(jsonString: arguments)
        return try await execute(typedArguments: typedArgs)
    }
}

/// Tool execution errors
enum ToolError: LocalizedError {
    case invalidArguments(String)
    case executionFailed(String)
    case permissionDenied(String)
    case notAvailable(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidArguments(let msg): return "Invalid arguments: \(msg)"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        case .permissionDenied(let msg): return "Permission denied: \(msg)"
        case .notAvailable(let msg): return "Not available: \(msg)"
        }
    }
}

