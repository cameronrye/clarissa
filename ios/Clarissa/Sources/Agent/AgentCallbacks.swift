import Foundation

/// Callbacks for agent events during execution
@MainActor
protocol AgentCallbacks: AnyObject {
    /// Called when the agent starts thinking
    func onThinking()
    
    /// Called when a tool is about to be called
    func onToolCall(name: String, arguments: String)
    
    /// Called to request user confirmation for a tool
    /// Returns true if the user approves, false to reject
    func onToolConfirmation(name: String, arguments: String) async -> Bool
    
    /// Called when a tool execution completes
    func onToolResult(name: String, result: String)
    
    /// Called when a response chunk is received (streaming)
    func onStreamChunk(chunk: String)
    
    /// Called when the final response is ready
    func onResponse(content: String)
    
    /// Called when an error occurs
    func onError(error: Error)
}

/// Default implementation that does nothing
extension AgentCallbacks {
    func onThinking() {}
    func onToolCall(name: String, arguments: String) {}
    func onToolConfirmation(name: String, arguments: String) async -> Bool { true }
    func onToolResult(name: String, result: String) {}
    func onStreamChunk(chunk: String) {}
    func onResponse(content: String) {}
    func onError(error: Error) {}
}

