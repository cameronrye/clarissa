import Foundation

/// Configuration for the agent
struct AgentConfig {
    var maxIterations: Int = 10
    var autoApprove: Bool = false
}

/// Errors that can occur during agent execution
enum AgentError: LocalizedError {
    case maxIterationsReached
    case noProvider
    case toolNotFound(String)
    case toolExecutionFailed(String, Error)
    
    var errorDescription: String? {
        switch self {
        case .maxIterationsReached:
            return "Maximum iterations reached. The agent may be stuck in a loop."
        case .noProvider:
            return "No LLM provider configured."
        case .toolNotFound(let name):
            return "Tool '\(name)' not found."
        case .toolExecutionFailed(let name, let error):
            return "Tool '\(name)' failed: \(error.localizedDescription)"
        }
    }
}

/// The Clarissa Agent - implements the ReAct loop pattern
@MainActor
final class Agent: ObservableObject {
    private var messages: [Message] = []
    private let config: AgentConfig
    private let toolRegistry: ToolRegistry
    private var provider: (any LLMProvider)?

    weak var callbacks: AgentCallbacks?

    init(
        config: AgentConfig = AgentConfig(),
        toolRegistry: ToolRegistry = .shared
    ) {
        self.config = config
        self.toolRegistry = toolRegistry
    }
    
    /// Set the LLM provider
    func setProvider(_ provider: any LLMProvider) {
        self.provider = provider
    }
    
    /// Build the system prompt with tool names and memories
    private func buildSystemPrompt() async -> String {
        let toolNames = toolRegistry.getToolNames()
        let toolList = toolNames.map { "- \($0)" }.joined(separator: "\n")
        
        var prompt = """
        You are Clarissa, a helpful AI assistant with access to tools.
        
        You can use the following tools:
        \(toolList)
        
        When you need to perform actions or interact with the system, use the appropriate tool.
        Always explain what you're doing and provide clear, helpful responses.
        If a tool fails, explain the error and suggest alternatives if possible.
        
        Be concise but thorough. Format your responses for mobile display.
        """
        
        // Add memories if any
        if let memoriesPrompt = await MemoryManager.shared.getForPrompt() {
            prompt += "\n\n\(memoriesPrompt)"
        }
        
        return prompt
    }
    
    /// Run the agent with a user message
    func run(_ userMessage: String) async throws -> String {
        guard let provider = provider else {
            throw AgentError.noProvider
        }
        
        // Update system prompt
        let systemPrompt = await buildSystemPrompt()
        if messages.isEmpty || messages.first?.role != .system {
            messages.insert(.system(systemPrompt), at: 0)
        } else {
            messages[0] = .system(systemPrompt)
        }
        
        // Add user message
        messages.append(.user(userMessage))
        
        // Get available tools
        let tools = toolRegistry.getDefinitions()
        
        // ReAct loop
        for _ in 0..<config.maxIterations {
            callbacks?.onThinking()
            
            // Get LLM response with streaming
            var fullContent = ""
            var toolCalls: [ToolCall] = []
            
            for try await chunk in provider.streamComplete(messages: messages, tools: tools) {
                if let content = chunk.content {
                    fullContent += content
                    callbacks?.onStreamChunk(chunk: content)
                }
                if let calls = chunk.toolCalls {
                    toolCalls = calls
                }
            }
            
            // Create assistant message
            let assistantMessage = Message.assistant(
                fullContent,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
            messages.append(assistantMessage)
            
            // Check for tool calls
            if !toolCalls.isEmpty {
                for toolCall in toolCalls {
                    callbacks?.onToolCall(name: toolCall.name, arguments: toolCall.arguments)
                    
                    // Check confirmation if needed
                    let needsConfirmation = toolRegistry.requiresConfirmation(toolCall.name)
                    if !config.autoApprove && needsConfirmation {
                        let approved = await callbacks?.onToolConfirmation(
                            name: toolCall.name,
                            arguments: toolCall.arguments
                        ) ?? true
                        
                        if !approved {
                            let result = Message.tool(
                                callId: toolCall.id,
                                name: toolCall.name,
                                content: "{\"rejected\": true, \"message\": \"User rejected this tool execution\"}"
                            )
                            messages.append(result)
                            callbacks?.onToolResult(name: toolCall.name, result: "Rejected by user")
                            continue
                        }
                    }
                    
                    // Execute tool
                    do {
                        let result = try await toolRegistry.execute(name: toolCall.name, arguments: toolCall.arguments)
                        let toolMessage = Message.tool(callId: toolCall.id, name: toolCall.name, content: result)
                        messages.append(toolMessage)
                        callbacks?.onToolResult(name: toolCall.name, result: result)
                    } catch {
                        let errorResult = "{\"error\": \"\(error.localizedDescription)\"}"
                        let toolMessage = Message.tool(callId: toolCall.id, name: toolCall.name, content: errorResult)
                        messages.append(toolMessage)
                        callbacks?.onToolResult(name: toolCall.name, result: errorResult)
                    }
                }
                continue // Continue loop for next response
            }
            
            // No tool calls - final response
            callbacks?.onResponse(content: fullContent)
            return fullContent
        }
        
        throw AgentError.maxIterationsReached
    }
    
    /// Reset conversation (keep system prompt)
    func reset() {
        let systemMessage = messages.first { $0.role == .system }
        messages = systemMessage.map { [$0] } ?? []
    }
    
    /// Get conversation history
    func getHistory() -> [Message] {
        messages
    }
    
    /// Load messages from a saved session
    func loadMessages(_ savedMessages: [Message]) {
        let systemMessage = messages.first { $0.role == .system }
        let filtered = savedMessages.filter { $0.role != .system }
        messages = (systemMessage.map { [$0] } ?? []) + filtered
    }
    
    /// Get messages for saving (excluding system)
    func getMessagesForSave() -> [Message] {
        messages.filter { $0.role != .system }
    }
}

