import Foundation

/// Configuration for the agent
struct AgentConfig {
    var maxIterations: Int = ClarissaConstants.defaultMaxIterations
    var autoApprove: Bool = ClarissaConstants.defaultAutoApprove
}

// MARK: - Token Management

/// Constants for Foundation Models context window management
/// Community insight: "The 4,096 token limit is for input + output combined, not separate"
enum TokenBudget {
    /// Total context window for Foundation Models
    static let totalContextWindow = 4096

    /// Reserve tokens for system instructions
    static let systemReserve = 300

    /// Reserve tokens for the expected response
    static let responseReserve = 1500

    /// Maximum tokens for conversation history
    static let maxHistoryTokens = totalContextWindow - systemReserve - responseReserve

    /// Estimate tokens for a string
    /// Community insight: "For Latin text: ~3-4 characters per token, CJK: ~1 char per token"
    static func estimate(_ text: String) -> Int {
        let asciiCount = text.unicodeScalars.filter { $0.isASCII }.count
        let isMainlyLatin = asciiCount > text.count / 2
        return isMainlyLatin ? max(1, text.count / 4) : text.count
    }

    /// Estimate tokens for an array of messages
    static func estimate(_ messages: [Message]) -> Int {
        messages.reduce(0) { $0 + estimate($1.content) }
    }
}

/// Statistics about current context window usage
struct ContextStats: Sendable {
    let currentTokens: Int
    let maxTokens: Int
    let usagePercent: Double
    let systemTokens: Int
    let userTokens: Int
    let assistantTokens: Int
    let toolTokens: Int
    let messageCount: Int
    let trimmedCount: Int

    /// Returns true if context is nearly full (>80%)
    var isNearLimit: Bool {
        usagePercent >= 0.8
    }

    /// Returns true if context is critically full (>95%)
    var isCritical: Bool {
        usagePercent >= 0.95
    }

    /// Empty stats for initial state
    static let empty = ContextStats(
        currentTokens: 0,
        maxTokens: TokenBudget.maxHistoryTokens,
        usagePercent: 0,
        systemTokens: 0,
        userTokens: 0,
        assistantTokens: 0,
        toolTokens: 0,
        messageCount: 0,
        trimmedCount: 0
    )
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
    private var trimmedCount: Int = 0

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
    
    /// Build the system prompt with memories
    /// Community insight: "Include examples in your session instructions to guide tool usage"
    /// Note: Tool names are registered natively with the LLM provider
    private func buildSystemPrompt() async -> String {
        // Instructions should be in English for best results per community insight
        var prompt = """
        You are Clarissa, a helpful AI assistant.

        TOOL USAGE GUIDELINES:
        - When the user asks about weather or temperature, use the weather tool.
        - When the user wants to create, list, or search calendar events, use the calendar tool.
        - When the user asks to find or look up a contact, use the contacts tool.
        - When the user wants to create or list reminders/tasks, use the reminders tool.
        - When the user asks for their location or "where am I", use the location tool.
        - When the user needs to calculate or do math, use the calculator tool.
        - When the user wants to fetch or read a webpage/URL, use the web_fetch tool.
        - When the user asks you to remember something, use the remember tool.

        RESPONSE GUIDELINES:
        - Always explain what you're doing and provide clear, helpful responses.
        - If a tool fails, explain the error and suggest alternatives if possible.
        - Be concise but thorough. Format your responses for mobile display.
        - For non-tool questions, respond directly without using tools.
        """

        // Add memories if any (sanitized in MemoryManager)
        if let memoriesPrompt = await MemoryManager.shared.getForPrompt() {
            prompt += "\n\n\(memoriesPrompt)"
        }

        return prompt
    }
    
    /// Trim conversation history to fit within token budget
    /// Keeps system prompt and at least the last user message
    private func trimHistoryIfNeeded() {
        // Don't trim if we only have system + 1 message
        guard messages.count > 2 else { return }

        // Get non-system messages for token counting
        let historyMessages = messages.filter { $0.role != .system }
        var tokenCount = TokenBudget.estimate(historyMessages)

        // Safety guard: limit iterations to prevent infinite loop
        // Max iterations = initial message count (can't remove more than we have)
        let maxIterations = messages.count
        var iterations = 0
        var removedThisPass = 0

        // Trim from the beginning (oldest first) until within budget
        // Keep at least the last 2 messages (user + response pair)
        while tokenCount > TokenBudget.maxHistoryTokens && messages.count > 3 && iterations < maxIterations {
            iterations += 1

            // Find first non-system message to remove
            if let firstNonSystemIndex = messages.firstIndex(where: { $0.role != .system }) {
                let removed = messages.remove(at: firstNonSystemIndex)
                tokenCount -= TokenBudget.estimate(removed.content)
                removedThisPass += 1
            } else {
                break
            }
        }

        // Track cumulative trimmed count
        trimmedCount += removedThisPass
        if removedThisPass > 0 {
            ClarissaLogger.agent.info("Trimmed \(removedThisPass) messages, total trimmed: \(self.trimmedCount)")
        }

        if iterations >= maxIterations {
            ClarissaLogger.agent.warning("Token trimming reached max iterations, stopping to prevent infinite loop")
        }
    }

    /// Run the agent with a user message
    func run(_ userMessage: String) async throws -> String {
        ClarissaLogger.agent.info("Starting agent run with message: \(userMessage.prefix(50), privacy: .public)...")

        guard let provider = provider else {
            ClarissaLogger.agent.error("No provider configured")
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

        // Trim history to fit within Foundation Models context window
        trimHistoryIfNeeded()

        // Get available tools (limited by provider capability)
        let tools = toolRegistry.getDefinitionsLimited(provider.maxTools)
        
        // ReAct loop
        for _ in 0..<config.maxIterations {
            callbacks?.onThinking()
            
            // Get LLM response with streaming
            var fullContent = ""
            var toolCalls: [ToolCall] = []
            
            for try await chunk in provider.streamComplete(messages: messages, tools: tools) {
                // Check for task cancellation during streaming
                try Task.checkCancellation()

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
                        ClarissaLogger.tools.info("Executing tool: \(toolCall.name, privacy: .public)")
                        let result = try await toolRegistry.execute(name: toolCall.name, arguments: toolCall.arguments)
                        let toolMessage = Message.tool(callId: toolCall.id, name: toolCall.name, content: result)
                        messages.append(toolMessage)
                        callbacks?.onToolResult(name: toolCall.name, result: result)
                        ClarissaLogger.tools.info("Tool \(toolCall.name, privacy: .public) completed successfully")
                    } catch {
                        ClarissaLogger.tools.error("Tool \(toolCall.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        let errorResult = Self.encodeErrorJSON(error.localizedDescription)
                        let toolMessage = Message.tool(callId: toolCall.id, name: toolCall.name, content: errorResult)
                        messages.append(toolMessage)
                        callbacks?.onToolResult(name: toolCall.name, result: errorResult)
                    }
                }
                continue // Continue loop for next response
            }

            // No tool calls - final response
            ClarissaLogger.agent.info("Agent run completed with response")
            callbacks?.onResponse(content: fullContent)
            return fullContent
        }

        ClarissaLogger.agent.warning("Agent reached max iterations")
        throw AgentError.maxIterationsReached
    }
    
    /// Reset conversation (keep system prompt)
    func reset() {
        let systemMessage = messages.first { $0.role == .system }
        messages = systemMessage.map { [$0] } ?? []
        trimmedCount = 0
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

    /// Get current context statistics
    func getContextStats() -> ContextStats {
        var systemTokens = 0
        var userTokens = 0
        var assistantTokens = 0
        var toolTokens = 0

        for message in messages {
            let tokens = TokenBudget.estimate(message.content)
            switch message.role {
            case .system:
                systemTokens += tokens
            case .user:
                userTokens += tokens
            case .assistant:
                assistantTokens += tokens
            case .tool:
                toolTokens += tokens
            }
        }

        let historyTokens = userTokens + assistantTokens + toolTokens
        let usagePercent = Double(historyTokens) / Double(TokenBudget.maxHistoryTokens)

        return ContextStats(
            currentTokens: historyTokens,
            maxTokens: TokenBudget.maxHistoryTokens,
            usagePercent: min(1.0, usagePercent),
            systemTokens: systemTokens,
            userTokens: userTokens,
            assistantTokens: assistantTokens,
            toolTokens: toolTokens,
            messageCount: messages.count,
            trimmedCount: trimmedCount
        )
    }

    // MARK: - JSON Helpers

    /// Encode an error message as JSON using proper serialization
    /// This avoids issues with special characters that would break string interpolation
    private static func encodeErrorJSON(_ message: String) -> String {
        let errorDict: [String: Any] = ["error": message]
        if let data = try? JSONSerialization.data(withJSONObject: errorDict),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        // Fallback with escaped message if serialization fails
        return "{\"error\": \"Tool execution failed\"}"
    }
}

