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

