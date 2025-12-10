import Foundation

/// Definition of a tool that can be called by the LLM
struct ToolDefinition: @unchecked Sendable {
    let name: String
    let description: String
    let parameters: [String: Any]

    init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = parameters
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

