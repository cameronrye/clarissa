import Foundation

// MARK: - Sendable JSON Value

/// A type-safe, Sendable representation of JSON values
/// Used for tool parameters to ensure thread safety in Swift 6 concurrency
enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Convert to Any for JSON serialization
    var toAny: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.toAny }
        case .object(let v): return v.mapValues { $0.toAny }
        }
    }

    /// Create from Any (for interop with existing code)
    static func from(_ value: Any) -> JSONValue {
        switch value {
        case is NSNull:
            return .null
        case let v as Bool:
            return .bool(v)
        case let v as Int:
            return .int(v)
        case let v as Double:
            return .double(v)
        case let v as String:
            return .string(v)
        case let v as [Any]:
            return .array(v.map { from($0) })
        case let v as [String: Any]:
            return .object(v.mapValues { from($0) })
        default:
            return .string(String(describing: value))
        }
    }
}

/// Definition of a tool that can be called by the LLM
/// Now fully Sendable with type-safe JSON parameters
struct ToolDefinition: Sendable {
    let name: String
    let description: String
    let parameters: JSONValue

    init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    /// Convenience initializer for existing code using [String: Any]
    init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = JSONValue.from(parameters)
    }

    /// Get parameters as [String: Any] for serialization
    var parametersAsDictionary: [String: Any] {
        if case .object(let dict) = parameters {
            return dict.mapValues { $0.toAny }
        }
        return [:]
    }
}

/// Protocol for LLM providers
protocol LLMProvider: Sendable {
    /// Provider name for display
    var name: String { get }
    
    /// Check if the provider is available
    var isAvailable: Bool { get async }
    
    /// Maximum number of tools this provider can handle effectively
    var maxTools: Int { get }
    
    /// Stream a completion from the LLM
    func streamComplete(
        messages: [Message],
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamChunk, Error>
    
    /// Non-streaming completion (convenience)
    func complete(
        messages: [Message],
        tools: [ToolDefinition]
    ) async throws -> Message
}

/// Default implementation for non-streaming
extension LLMProvider {
    func complete(messages: [Message], tools: [ToolDefinition]) async throws -> Message {
        var content = ""
        var toolCalls: [ToolCall] = []
        
        for try await chunk in streamComplete(messages: messages, tools: tools) {
            if let c = chunk.content {
                content += c
            }
            if let calls = chunk.toolCalls {
                toolCalls = calls
            }
        }
        
        return .assistant(content, toolCalls: toolCalls.isEmpty ? nil : toolCalls)
    }
}

