import Foundation

/// Configuration for the agent
struct AgentConfig {
    var maxIterations: Int = ClarissaConstants.defaultMaxIterations
}

// MARK: - Token Management

/// Constants for Foundation Models context window management
/// Uses values from ClarissaConstants for centralized configuration
enum TokenBudget {
    /// Total context window for Foundation Models
    static let totalContextWindow = ClarissaConstants.foundationModelsContextWindow

    /// Reserve tokens for system instructions
    static let systemReserve = ClarissaConstants.tokenSystemReserve

    /// Reserve tokens for tool schemas (~100 per tool with @Generable)
    static let toolSchemaReserve = ClarissaConstants.tokenToolSchemaReserve

    /// Reserve tokens for the expected response
    static let responseReserve = ClarissaConstants.tokenResponseReserve

    /// Maximum tokens for conversation history
    /// Accounts for system prompt, tool schemas, and expected response
    static let maxHistoryTokens = totalContextWindow - systemReserve - toolSchemaReserve - responseReserve

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
    /// Optimized for Apple Foundation Models with:
    /// - Concise, imperative instructions (saves tokens)
    /// - Clear tool triggers with few-shot examples
    /// - Explicit negative rules to avoid unnecessary tool use
    /// Community insights: "Instructions in English work best", "Use CAPS for critical rules"
    private func buildSystemPrompt() async -> String {
        // Keep prompt concise (~600 chars = ~150 tokens) to maximize context for conversation
        var prompt = """
        You are Clarissa, an iOS assistant.

        ALWAYS USE TOOLS FOR:
        - Weather/temperature -> weather tool
        - Math/tip/percent -> calculator tool
        - Schedule/meeting/event -> calendar tool
        - Task/reminder/to-do -> reminders tool
        - Phone/email/contact -> contacts tool
        - "Where am I" -> location tool
        - "Remember that..." -> remember tool

        DO NOT USE TOOLS FOR:
        - General knowledge questions
        - Opinions or advice
        - Greetings or chat

        EXAMPLES:
        "Weather?" -> weather (no params = current location)
        "Weather in Paris" -> weather(location="Paris")
        "What's 20% of 85?" -> calculator(expression="85 * 0.20")
        "Meeting tomorrow 2pm" -> calendar(action=create, title, startDate)
        "Remind me to call Bob" -> reminders(action=create, title="Call Bob")

        RESPONSE RULES:
        - Be brief (1-2 sentences)
        - State result, not process
        - If tool fails, explain and suggest alternative
        """

        // Add memories if any (sanitized in MemoryManager)
        if let memoriesPrompt = await MemoryManager.shared.getForPrompt() {
            prompt += "\n\nCONTEXT:\n\(memoriesPrompt)"
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
        // For providers that handle tools natively (e.g., Foundation Models),
        // we still pass tool definitions but they're used by the session internally
        let tools = toolRegistry.getDefinitionsLimited(provider.maxTools)

        // Check if provider handles tools natively (e.g., Apple Foundation Models)
        // Native providers execute tools within the LLM session - no manual execution needed
        let nativeToolHandling = provider.handlesToolsNatively
        if nativeToolHandling {
            ClarissaLogger.agent.info("Using native tool handling (tools executed within LLM session)")
        }

        // ReAct loop
        // For native tool providers, this typically completes in one iteration
        // since tools are executed internally by the LLM session
        for _ in 0..<config.maxIterations {
            callbacks?.onThinking()

            // Get LLM response with streaming
            var fullContent = ""
            var toolCalls: [ToolCall] = []

            for try await chunk in provider.streamComplete(messages: messages, tools: tools) {
                // Check for task cancellation during streaming
                try Task.checkCancellation()

                if let content = chunk.content, content != "null" {
                    // Filter out literal "null" string which models sometimes output
                    // when confused about tool calling
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

            // For providers with native tool handling, skip manual tool execution
            // The LLM session has already executed tools and incorporated results
            if nativeToolHandling {
                ClarissaLogger.agent.info("Agent run completed (native tool handling)")
                callbacks?.onResponse(content: fullContent)
                return fullContent
            }

            // Check for tool calls (only for non-native providers like OpenRouter)
            if !toolCalls.isEmpty {
                for toolCall in toolCalls {
                    callbacks?.onToolCall(name: toolCall.name, arguments: toolCall.arguments)

                    // Execute tool
                    do {
                        ClarissaLogger.tools.info("Executing tool: \(toolCall.name, privacy: .public)")
                        let result = try await toolRegistry.execute(name: toolCall.name, arguments: toolCall.arguments)
                        let toolMessage = Message.tool(callId: toolCall.id, name: toolCall.name, content: result)
                        messages.append(toolMessage)
                        callbacks?.onToolResult(name: toolCall.name, result: result, success: true)
                        ClarissaLogger.tools.info("Tool \(toolCall.name, privacy: .public) completed successfully")
                    } catch {
                        ClarissaLogger.tools.error("Tool \(toolCall.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        // Include a recovery suggestion to help the model provide useful feedback
                        let suggestion = Self.getSuggestion(for: toolCall.name, error: error)
                        let errorResult = Self.encodeErrorJSON(error.localizedDescription, suggestion: suggestion)
                        let toolMessage = Message.tool(callId: toolCall.id, name: toolCall.name, content: errorResult)
                        messages.append(toolMessage)
                        callbacks?.onToolResult(name: toolCall.name, result: errorResult, success: false)
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
    /// Note: This only clears local message history. Call resetForNewConversation()
    /// to also reset the LLM provider session.
    func reset() {
        let systemMessage = messages.first { $0.role == .system }
        messages = systemMessage.map { [$0] } ?? []
        trimmedCount = 0
    }

    /// Reset for a completely new conversation
    /// This clears both local message history AND the LLM provider's session
    /// to prevent context bleeding between conversations
    func resetForNewConversation() async {
        reset()
        // Also reset the provider session to clear any cached transcript
        await provider?.resetSession()
        ClarissaLogger.agent.info("Agent reset for new conversation (including provider session)")
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
    /// Includes a suggestion for recovery when possible
    /// This avoids issues with special characters that would break string interpolation
    private static func encodeErrorJSON(_ message: String, suggestion: String? = nil) -> String {
        var errorDict: [String: Any] = ["error": message]
        if let suggestion = suggestion {
            errorDict["suggestion"] = suggestion
        }
        if let data = try? JSONSerialization.data(withJSONObject: errorDict),
           let jsonString = String(data: data, encoding: .utf8) {
            return jsonString
        }
        // Fallback with escaped message if serialization fails
        return "{\"error\": \"Tool execution failed\"}"
    }

    /// Get a recovery suggestion for a tool error
    /// Provides context-aware suggestions based on the tool name and error
    private static func getSuggestion(for toolName: String, error: Error) -> String? {
        let errorMessage = error.localizedDescription.lowercased()

        switch toolName {
        case "weather":
            if errorMessage.contains("location") || errorMessage.contains("denied") {
                return "Try specifying a city name like 'weather in San Francisco'"
            }
            if errorMessage.contains("timeout") {
                return "Location request timed out. Please try again or specify a city name."
            }
        case "calendar":
            if errorMessage.contains("access") || errorMessage.contains("denied") {
                return "Calendar access is required. Please enable it in Settings > Privacy > Calendars."
            }
            if errorMessage.contains("title") {
                return "Please specify what event you'd like to create."
            }
        case "contacts":
            if errorMessage.contains("access") || errorMessage.contains("denied") {
                return "Contacts access is required. Please enable it in Settings > Privacy > Contacts."
            }
        case "reminders":
            if errorMessage.contains("access") || errorMessage.contains("denied") {
                return "Reminders access is required. Please enable it in Settings > Privacy > Reminders."
            }
        case "location":
            if errorMessage.contains("denied") || errorMessage.contains("authorization") {
                return "Location access is required. Please enable it in Settings > Privacy > Location Services."
            }
        case "web_fetch":
            if errorMessage.contains("invalid") || errorMessage.contains("url") {
                return "Please provide a valid URL starting with http:// or https://"
            }
            if errorMessage.contains("timeout") || errorMessage.contains("network") {
                return "Network error. Please check your connection and try again."
            }
        case "calculator":
            if errorMessage.contains("expression") || errorMessage.contains("invalid") {
                return "Please check the math expression format. Example: '100 * 0.15' for 15% of 100."
            }
        default:
            break
        }

        return nil
    }
}

