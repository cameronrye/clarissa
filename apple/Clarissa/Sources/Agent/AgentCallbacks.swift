import Foundation

/// Callbacks for agent events during execution
@MainActor
public protocol AgentCallbacks: AnyObject {
    /// Called when the agent starts thinking
    func onThinking()

    /// Called when a tool is about to be called
    func onToolCall(name: String, arguments: String)

    /// Called when a tool execution completes
    /// - Parameters:
    ///   - name: The tool name
    ///   - result: The result string (may be error JSON if failed)
    ///   - success: Whether the tool executed successfully
    func onToolResult(name: String, result: String, success: Bool)

    /// Called when a response chunk is received (streaming)
    func onStreamChunk(chunk: String)

    /// Called when the final response is ready
    func onResponse(content: String)

    /// Called when an error occurs
    func onError(error: Error)

    /// Called when proactive context was prefetched and injected into the prompt
    func onProactiveContext(labels: [String])

    /// Called when a tool chain is about to start executing
    func onChainStart(chain: ToolChain)

    /// Called when a tool chain step begins
    func onChainStepStart(stepIndex: Int, step: ToolChainStep)

    /// Called when a tool chain step completes
    func onChainStepComplete(stepIndex: Int, step: ToolChainStep, result: String, success: Bool)

    /// Called when all chain steps are done and results are being synthesized
    func onChainComplete(result: ToolChainResult)
}

/// Default implementation that does nothing
public extension AgentCallbacks {
    func onThinking() {}
    func onToolCall(name: String, arguments: String) {}
    func onToolResult(name: String, result: String, success: Bool) {}
    func onStreamChunk(chunk: String) {}
    func onResponse(content: String) {}
    func onError(error: Error) {}
    func onProactiveContext(labels: [String]) {}
    func onChainStart(chain: ToolChain) {}
    func onChainStepStart(stepIndex: Int, step: ToolChainStep) {}
    func onChainStepComplete(stepIndex: Int, step: ToolChainStep, result: String, success: Bool) {}
    func onChainComplete(result: ToolChainResult) {}
}

