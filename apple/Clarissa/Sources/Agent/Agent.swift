import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Configuration for the agent
public struct AgentConfig {
    public var maxIterations: Int = ClarissaConstants.defaultMaxIterations
    public var maxRetries: Int = 3
    public var baseRetryDelay: TimeInterval = 1.0  // seconds

    public init(
        maxIterations: Int = ClarissaConstants.defaultMaxIterations,
        maxRetries: Int = 3,
        baseRetryDelay: TimeInterval = 1.0
    ) {
        self.maxIterations = maxIterations
        self.maxRetries = maxRetries
        self.baseRetryDelay = baseRetryDelay
    }
}

// MARK: - Retry Helper

/// Retry configuration for handling rate limits and transient errors
enum RetryHelper {
    /// Check if an error is retryable (rate limits, transient failures)
    static func isRetryable(_ error: Error) -> Bool {
        // Check for Foundation Models rate limiting
        if let fmError = error as? FoundationModelsError {
            switch fmError {
            case .rateLimited, .concurrentRequests:
                return true
            default:
                return false
            }
        }
        // Check for URLSession rate limit responses
        if let urlError = error as? URLError {
            return urlError.code == .timedOut || urlError.code == .networkConnectionLost
        }
        return false
    }

    /// Calculate delay with exponential backoff
    static func delay(forAttempt attempt: Int, baseDelay: TimeInterval) -> TimeInterval {
        let delay = baseDelay * pow(2.0, Double(attempt))
        // Add jitter to prevent thundering herd
        let jitter = Double.random(in: 0...0.5)
        return min(delay + jitter, 30.0)  // Cap at 30 seconds
    }
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

// MARK: - System Prompt Budget

/// Tracks running token usage as sections are added to the system prompt.
/// Enforces per-section caps and drops lower-priority content when the
/// total budget (ClarissaConstants.tokenSystemReserve) is exceeded.
struct SystemPromptBudget {
    private let totalBudget: Int
    private(set) var usedTokens: Int = 0

    init(totalBudget: Int = ClarissaConstants.tokenSystemReserve) {
        self.totalBudget = totalBudget
    }

    /// Remaining tokens available in the system prompt budget
    var remaining: Int { max(0, totalBudget - usedTokens) }

    /// Try to add a section to the system prompt within the given cap.
    /// Returns the (possibly truncated) text, or nil if no budget remains.
    mutating func add(_ text: String, cap: Int) -> String? {
        guard remaining > 0 else { return nil }
        let effectiveCap = min(cap, remaining)
        let estimated = TokenBudget.estimate(text)

        if estimated <= effectiveCap {
            usedTokens += estimated
            return text
        }

        // Truncate to fit — approximate 4 chars per token for truncation point
        let maxChars = effectiveCap * 4
        guard maxChars > 20 else { return nil }
        let truncated = String(text.prefix(maxChars - 3)) + "..."
        usedTokens += effectiveCap
        return truncated
    }
}

// MARK: - Tool Call Validation

/// Validates tool calls against user intent and checks response coherence.
/// Catches cases where the on-device model selects the wrong tool (e.g., calculator → calendar)
/// or fabricates results that don't match the user's question.
enum ToolCallValidator {

    // MARK: - Tool Mismatch Detection

    /// Patterns that strongly indicate a specific tool should be used
    private static let mathPatterns: [String] = [
        #"\d+\s*[+\-*/×÷%^]\s*\d+"#,      // "9*8", "3 + 4"
        #"what(?:'s| is)\s+\d+\s*[+\-*/×÷%^]"#, // "what's 9*8"
        #"\b(calculate|compute|solve)\b"#,   // "calculate 15+3"
        #"\b(square root|sqrt|factorial)\b"#,
        #"\d+%\s+of\s+\d+"#,               // "20% of 85"
    ]

    private static let calendarPatterns: [String] = [
        #"\b(schedule|meeting|appointment|event|calendar|busy|free)\b"#,
        #"\b(today|tomorrow|tonight|this morning|this afternoon|this evening)\b"#,
        #"\b(next (monday|tuesday|wednesday|thursday|friday|saturday|sunday))\b"#,
    ]

    private static let weatherPatterns: [String] = [
        #"\b(weather|forecast|temperature|rain|snow|sunny|cloudy|humid|wind)\b"#,
        #"\b(umbrella|jacket|coat|cold outside|hot outside)\b"#,
    ]

    private static let reminderPatterns: [String] = [
        #"\b(remind|reminder|to-?do|task)\b"#,
    ]

    /// Check if a tool call is a clear mismatch for the user's message.
    /// Returns a description of the mismatch, or nil if the call seems reasonable.
    static func detectMismatch(userMessage: String, toolName: String) -> String? {
        let lower = userMessage.lowercased()

        // Math question → should use calculator, not anything else
        if matchesAny(lower, patterns: mathPatterns) && toolName != "calculator" {
            return "Message looks like math (\(userMessage.prefix(30))...) but tool '\(toolName)' was selected instead of 'calculator'"
        }

        // Calendar question → should not use calculator
        if toolName == "calendar" && !matchesAny(lower, patterns: calendarPatterns) && matchesAny(lower, patterns: mathPatterns) {
            return "No calendar intent detected but 'calendar' was called for what appears to be a math question"
        }

        return nil
    }

    // MARK: - Response Coherence Check

    /// Check if the response is coherent with the user's query.
    /// Returns a corrected response if incoherent, or nil if the response seems fine.
    static func checkCoherence(userMessage: String, response: String, toolExecutions: [(name: String, result: String)]) -> String? {
        let lowerQuery = userMessage.lowercased()
        let lowerResponse = response.lowercased()

        // Case 1: Math question but response is about something else entirely
        if matchesAny(lowerQuery, patterns: mathPatterns) {
            // Check if any non-calculator tool was called — strong signal of wrong tool selection
            let calledWrongTool = !toolExecutions.isEmpty && !toolExecutions.contains(where: { $0.name == "calculator" })

            let irrelevantPhrases = [
                // Scheduling/calendar
                "scheduled", "meeting", "appointment", "calendar", "event", "booked",
                // Weather
                "weather", "forecast", "temperature", "°f", "°c", "sunny", "cloudy",
                "windy", "humidity", "rain", "snow",
                // Location
                "latitude", "longitude", "your location",
                // Contacts
                "phone number", "email address", "contact",
            ]
            let hasIrrelevantContent = irrelevantPhrases.contains { lowerResponse.contains($0) }

            if (hasIrrelevantContent || calledWrongTool) && !matchesAny(lowerQuery, patterns: calendarPatterns) && !matchesAny(lowerQuery, patterns: weatherPatterns) {
                // The model answered a math question with an unrelated response
                ClarissaLogger.agent.warning("Coherence failure: math question got irrelevant response (wrongTool=\(calledWrongTool), irrelevant=\(hasIrrelevantContent))")

                // Try to compute the answer ourselves using a simple regex extraction
                if let corrected = attemptMathFallback(from: lowerQuery) {
                    return corrected
                }
                return "I wasn't able to calculate that correctly. Could you try asking again? For example: \"What is 9 times 8?\""
            }

            // Math question but no number in response at all
            let hasNumber = response.range(of: #"\b\d+\b"#, options: .regularExpression) != nil
            if !hasNumber && !lowerResponse.contains("calculator") && !lowerResponse.contains("error") {
                if let corrected = attemptMathFallback(from: lowerQuery) {
                    return corrected
                }
            }
        }

        // Case 2: Response claims an action was taken but no tool confirmed it
        let actionClaims = [
            "i've successfully scheduled",
            "i've scheduled",
            "i've created",
            "i've added",
            "i've deleted",
            "i've removed",
            "i've sent",
            "successfully created",
            "successfully scheduled",
            "successfully added",
        ]
        let claimsAction = actionClaims.contains { lowerResponse.contains($0) }
        if claimsAction && toolExecutions.isEmpty {
            ClarissaLogger.agent.warning("Coherence failure: response claims action but no tools were executed")
            return "I wasn't able to complete that action. Could you try again?"
        }

        return nil
    }

    // MARK: - Helpers

    private static func matchesAny(_ text: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Conversational Query Detection

    /// Patterns for messages that should be answered directly without tools.
    /// The on-device Foundation Model aggressively calls tools even for conversational
    /// queries like "What can you do?" — this filter catches those and strips tools
    /// before sending to the session.
    private static let conversationalPatterns: [String] = [
        // Greetings
        #"^(hi|hey|hello|good (morning|afternoon|evening)|howdy|yo|sup)\b"#,
        // Capability questions — allow words between "what" and "can/do you"
        #"\bwhat\b.{0,20}\b(can|do) you\b"#,
        #"\b(what are your|your capabilities|what('re| are) you able|how can you help)\b"#,
        // Thanks / farewell
        #"^(thanks?|thank you|thx|bye|goodbye|see you|good night|talk later)\b"#,
        // Meta / conversational
        #"^(who are you|what('s| is) your name|how do you work|tell me about yourself)\b"#,
        // Opinion / general knowledge (no tool needed)
        #"^(what do you think|in your opinion|can you explain|what does .+ mean)\b"#,
        // Affirmations / short replies unlikely to need tools
        #"^(ok|okay|sure|got it|cool|nice|great|awesome|perfect|sounds good|understood|yep|yes|no|nope)[\.\!\?]?$"#,
        // Creative writing — the on-device FM may trigger safety guardrails (process kill)
        // on open-ended generative prompts. Intercept these and handle locally.
        #"^(tell me a (story|joke|riddle|fun fact)|write (me )?a (story|poem|song|essay|letter))\b"#,
        #"^(make up|create|compose|imagine|invent) (a |an )?(story|poem|tale|song|scenario)\b"#,
        #"\b(write|generate) (fiction|creative|a paragraph|a chapter)\b"#,
    ]

    /// Returns true if the message is purely conversational and shouldn't trigger tool calls.
    static func isConversational(_ message: String) -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Short messages (≤3 words) that don't match any tool pattern are likely conversational
        let wordCount = lower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        if wordCount <= 3 && !matchesAnyToolPattern(lower) {
            return matchesAny(lower, patterns: conversationalPatterns)
        }

        return matchesAny(lower, patterns: conversationalPatterns) && !matchesAnyToolPattern(lower)
    }

    /// Check if message matches any known tool-triggering pattern
    private static func matchesAnyToolPattern(_ text: String) -> Bool {
        matchesAny(text, patterns: mathPatterns) ||
        matchesAny(text, patterns: calendarPatterns) ||
        matchesAny(text, patterns: weatherPatterns) ||
        matchesAny(text, patterns: reminderPatterns)
    }

    // MARK: - Creative Writing / Guardrail-Unsafe Detection

    /// Patterns for open-ended generative prompts that can trigger Foundation Models
    /// safety guardrails, causing a process kill (SIGKILL). These must be handled locally
    /// without ever sending to the FM session.
    private static let creativeWritingPatterns: [String] = [
        #"^tell me a (story|joke|riddle|fun fact)"#,
        #"^(write|create|compose|generate|make up) (me )?(a |an )?(story|poem|song|essay|letter|tale|limerick|haiku|narrative|script)"#,
        #"^(imagine|invent|make up) (a |an )?(story|scenario|world|character|adventure)"#,
        #"\b(write|generate) (fiction|creative writing|a paragraph about|a chapter)\b"#,
        #"^once upon a time\b"#,
    ]

    /// Returns true if the message is a creative/generative prompt that should be handled
    /// locally to avoid Foundation Models safety guardrails killing the process.
    static func isCreativeWriting(_ message: String) -> Bool {
        let lower = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return matchesAny(lower, patterns: creativeWritingPatterns)
    }

    /// Friendly response for creative writing prompts
    static let creativeWritingResponse = "I'm not set up for creative writing like stories or poems, but I'm great at helping with your calendar, reminders, weather, calculations, and contacts. What can I help you with?"

    // MARK: - Intent-Based Tool Restriction

    /// When a message clearly matches a single tool intent, restrict tools to just that tool.
    /// This prevents the on-device FM model from calling unrelated tools (e.g., weather/calendar
    /// for a math question), which causes unnecessary network requests and UI freezes.
    /// Returns the tool name to restrict to, or nil if all tools should be available.
    static func restrictedToolName(for message: String) -> String? {
        let lower = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let isMath = matchesAny(lower, patterns: mathPatterns)
        let isCalendar = matchesAny(lower, patterns: calendarPatterns)
        let isWeather = matchesAny(lower, patterns: weatherPatterns)
        let isReminder = matchesAny(lower, patterns: reminderPatterns)

        // Only restrict if exactly one intent matches — ambiguous queries get all tools
        let matches = [isMath, isCalendar, isWeather, isReminder].filter { $0 }.count
        guard matches == 1 else { return nil }

        if isMath { return "calculator" }
        if isCalendar { return "calendar" }
        if isWeather { return "weather" }
        if isReminder { return "reminders" }
        return nil
    }

    /// Attempt to extract and evaluate a simple math expression from the user message
    private static func attemptMathFallback(from message: String) -> String? {
        // Extract simple two-operand expressions like "9*8", "5+3", "100/4"
        let pattern = #"(\d+(?:\.\d+)?)\s*([+\-*/×÷])\s*(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              match.numberOfRanges == 4,
              let r1 = Range(match.range(at: 1), in: message),
              let r2 = Range(match.range(at: 2), in: message),
              let r3 = Range(match.range(at: 3), in: message),
              let a = Double(message[r1]),
              let b = Double(message[r3]) else {
            return nil
        }

        let op = String(message[r2])
        let result: Double
        switch op {
        case "+": result = a + b
        case "-": result = a - b
        case "*", "×": result = a * b
        case "/", "÷":
            guard b != 0 else { return "That's a division by zero — undefined!" }
            result = a / b
        default: return nil
        }

        // Format nicely (drop .0 for whole numbers)
        let formatted = result.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", result)
            : String(result)
        let aStr = a.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(a)) : String(a)
        let bStr = b.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(b)) : String(b)
        return "\(aStr) \(op) \(bStr) = \(formatted)"
    }

    /// Public accessor for math fallback — used by Agent when the calculator tool
    /// is unavailable but the intent restriction detected a math query.
    static func attemptMathFallbackPublic(from message: String) -> String? {
        attemptMathFallback(from: message)
    }
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
public final class Agent: ObservableObject {
    private var messages: [Message] = []
    private let config: AgentConfig
    private let toolRegistry: ToolRegistry
    private var provider: (any LLMProvider)?
    private var trimmedCount: Int = 0
    /// Summary of trimmed conversation for context preservation
    private var conversationSummary: String?
    /// Guard to prevent concurrent summarization requests
    private var isSummarizing: Bool = false
    /// Active conversation template (nil = default behavior)
    private(set) var currentTemplate: ConversationTemplate?
    /// Whether the current template's tools have already been prefetched
    private var templatePrefetchDone: Bool = false

    public weak var callbacks: AgentCallbacks?

    public init(
        config: AgentConfig = AgentConfig(),
        toolRegistry: ToolRegistry = .shared
    ) {
        self.config = config
        self.toolRegistry = toolRegistry
    }

    /// Set the LLM provider
    public func setProvider(_ provider: any LLMProvider) {
        self.provider = provider
    }

    /// Apply a conversation template
    public func applyTemplate(_ template: ConversationTemplate?) {
        self.currentTemplate = template
        self.templatePrefetchDone = false

        // Set max response tokens override on the provider
        if let provider = provider as? FoundationModelsProvider {
            provider.maxResponseTokensOverride = template?.maxResponseTokens
        } else if let provider = provider as? OpenRouterProvider {
            provider.maxResponseTokensOverride = template?.maxResponseTokens
        }

        // Template tool filtering is handled in run() via prefetch + exclusion.
        // We intentionally do NOT modify ToolSettings here — the template's toolNames
        // control which tools get prefetched, but all user-enabled tools remain available
        // for subsequent messages in the conversation.
    }
    
    /// Build the system prompt with budget-tracked sections.
    /// Each section is added in priority order and capped to prevent
    /// exceeding the 500-token system reserve.
    /// - Parameter proactiveContext: Optional prefetched context from ProactiveContext
    private func buildSystemPrompt(proactiveContext: String? = nil) async -> String {
        var budget = SystemPromptBudget()

        // Format current date/time for relative date understanding
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let currentTime = dateFormatter.string(from: Date())

        // Priority 1: Core instructions (non-negotiable)
        let corePrompt = """
        You are Clarissa, a personal assistant. Be warm but concise.
        Current time: \(currentTime)

        TOOLS: weather(location?), calculator(expression), calendar(action,title?,date?), reminders(action,title?), contacts(query), location(), remember(content), web_fetch(url), image_analysis(file_url)

        USE TOOLS for: weather, math, calendar, reminders, contacts, location, saving facts, fetching URLs, analyzing images/PDFs
        ANSWER DIRECTLY for: "[Image Analysis]" in message (use provided OCR/classifications), date/time questions, general knowledge, opinions, greetings, capability questions

        TOOL ROUTING (match the right tool to the request):
        - Math/numbers/calculations -> calculator ONLY (never calendar)
        - Weather/forecast/temperature -> weather
        - Events/meetings/schedule -> calendar
        - Tasks/to-do/remind -> reminders
        - People/phone/email -> contacts

        EXAMPLES:
        "Weather in Paris" -> weather(location="Paris")
        "What's 20% of 85?" -> calculator(expression="85*0.20")
        "What is 9*8?" -> calculator(expression="9*8")
        "Meeting tomorrow 2pm" -> calendar(action=create,title,startDate)

        WHEN ASKED about your capabilities or what you can do, list these:
        - Weather forecasts and conditions
        - Calendar management (view and create events)
        - Reminders (view and create tasks)
        - Math calculations
        - Contact lookup
        - Web page fetching and summarization
        - Image and PDF analysis
        - Saving personal notes to memory

        RULES:
        - Brief responses (1-2 sentences)
        - State result, not process
        - If request is ambiguous, ask one clarifying question before using tools
        - If tool fails, explain and suggest alternative
        - Use saved facts when user asks about their name/preferences
        - NEVER claim you performed an action (created, scheduled, deleted, sent) unless a tool confirmed success
        - ONLY report data that a tool actually returned — do not fabricate results
        """
        // Core prompt always included — budget tracks its size for remaining sections
        var prompt = budget.add(corePrompt, cap: ClarissaConstants.systemBudgetCore) ?? corePrompt

        // Priority 2: Template focus (if active)
        if let focus = currentTemplate?.systemPromptFocus {
            let templateText = "\n\nTEMPLATE MODE (\(currentTemplate?.name ?? "Custom")):\n\(focus)"
            if let section = budget.add(templateText, cap: ClarissaConstants.systemBudgetTemplate) {
                prompt += section
            }
        }

        // Priority 3: Conversation summary (only if messages were trimmed)
        if let summary = conversationSummary {
            let summaryText = "\n\nCONVERSATION SUMMARY (earlier context):\n\(summary)"
            if let section = budget.add(summaryText, cap: ClarissaConstants.systemBudgetSummary) {
                prompt += section
            }
        }

        // Priority 4: Memories
        var memoriesPrompt: String? = nil

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let recentUserContent = messages
                .filter { $0.role == .user }
                .suffix(3)
                .map { $0.content }
                .joined(separator: " ")

            if !recentUserContent.isEmpty {
                let topics = (try? await ContentTagger.shared.extractTopics(from: recentUserContent)) ?? []

                if !topics.isEmpty {
                    memoriesPrompt = await MemoryManager.shared.getRelevantForConversation(topics: topics)
                }
            }
        }
        #endif

        if memoriesPrompt == nil {
            memoriesPrompt = await MemoryManager.shared.getForPrompt()
        }

        if let memoriesPrompt = memoriesPrompt {
            let memoriesText = "\n\nCONTEXT:\n\(memoriesPrompt)"
            if let section = budget.add(memoriesText, cap: ClarissaConstants.systemBudgetMemories) {
                prompt += section
                ClarissaLogger.agent.info("System prompt includes memories (\(budget.usedTokens)/\(ClarissaConstants.tokenSystemReserve) tokens used)")
            } else {
                ClarissaLogger.agent.info("Memories dropped — system prompt budget exceeded (\(budget.usedTokens)/\(ClarissaConstants.tokenSystemReserve))")
            }
        }

        // Priority 5: Proactive context
        if let proactive = proactiveContext {
            let proactiveText = "\n\n\(proactive)"
            if let section = budget.add(proactiveText, cap: ClarissaConstants.systemBudgetProactive) {
                prompt += section
            } else {
                ClarissaLogger.agent.info("Proactive context dropped — system prompt budget exceeded")
            }
        }

        // Priority 6: Disabled tools list (lowest priority)
        let disabledTools = toolRegistry.getDisabledToolDescriptions()
        if !disabledTools.isEmpty {
            let disabledList = disabledTools.map { "- \($0.name): \($0.capability)" }.joined(separator: "\n")
            let disabledText = "\n\nDISABLED FEATURES (tell user to enable in Settings if they ask for these):\n\(disabledList)"
            if let section = budget.add(disabledText, cap: ClarissaConstants.systemBudgetDisabledTools) {
                prompt += section
            }
        }

        ClarissaLogger.agent.debug("System prompt budget: \(budget.usedTokens)/\(ClarissaConstants.tokenSystemReserve) tokens")
        return prompt
    }
    
    /// Prefetch tool data for a template's required tools.
    /// Runs all tools in parallel with a 3-second timeout per tool.
    /// Returns formatted context string and the names of tools that succeeded, or nil if all failed.
    private func prefetchTemplateTools(_ toolNames: [String]) async -> (context: String, fetchedTools: Set<String>)? {
        let enabledNames = ToolSettings.shared.enabledToolNames
        let validTools = toolNames.filter { enabledNames.contains($0) }
        guard !validTools.isEmpty else { return nil }

        // Default arguments for each tool when prefetching
        let defaultArgs: [String: String] = [
            "weather": "{}",
            "calendar": "{\"action\":\"list\"}",
            "reminders": "{\"action\":\"list\"}",
            "contacts": "{\"query\":\"recent\"}",
            "location": "{}",
        ]

        // Run all prefetches in parallel with per-tool timeout
        let results = await withTaskGroup(of: (String, String?).self, returning: [(String, String)].self) { group in
            for toolName in validTools {
                group.addTask { [toolRegistry] in
                    let args = defaultArgs[toolName] ?? "{}"
                    do {
                        let result = try await withThrowingTaskGroup(of: String.self) { inner in
                            inner.addTask {
                                try await toolRegistry.execute(name: toolName, arguments: args)
                            }
                            inner.addTask {
                                try await Task.sleep(for: .seconds(3))
                                throw CancellationError()
                            }
                            guard let first = try await inner.next() else { return "" }
                            inner.cancelAll()
                            return first
                        }
                        return (toolName, result as String?)
                    } catch {
                        ClarissaLogger.agent.info("Template prefetch for \(toolName) failed: \(error.localizedDescription)")
                        return (toolName, nil)
                    }
                }
            }

            var collected: [(String, String)] = []
            for await (name, result) in group {
                if let result { collected.append((name, result)) }
            }
            return collected
        }

        guard !results.isEmpty else { return nil }

        // Format results for injection into the system prompt
        var context = "PREFETCHED DATA (from template tools — use this data in your response, do NOT call these tools again):"
        for (name, result) in results {
            // Truncate each result to keep within budget
            let truncated = result.count > 500 ? String(result.prefix(497)) + "..." : result
            context += "\n[\(name)] \(truncated)"
        }

        // Fire tool callbacks so UI shows tool cards for the prefetched data
        for (name, result) in results {
            callbacks?.onToolCall(name: name, arguments: defaultArgs[name] ?? "{}")
            callbacks?.onToolResult(name: name, result: result, success: true)
        }

        let fetchedTools = Set(results.map(\.0))
        return (context: context, fetchedTools: fetchedTools)
    }

    /// Trim conversation history to fit within token budget
    /// Uses priority-based trimming: user messages first, then assistant, tool results last
    /// Triggers summarization when approaching the context limit
    private func trimHistoryIfNeeded() {
        // Don't trim if we only have system + 1 message
        guard messages.count > 2 else { return }

        // Get non-system messages for token counting
        let historyMessages = messages.filter { $0.role != .system }
        var tokenCount = TokenBudget.estimate(historyMessages)

        // Check if approaching limit — trigger summarization
        // Guard with isSummarizing to prevent duplicate concurrent summarization tasks
        let usageRatio = Double(tokenCount) / Double(TokenBudget.maxHistoryTokens)
        if usageRatio >= ClarissaConstants.summarizationThreshold && conversationSummary == nil && !isSummarizing {
            let messagesToSummarize = messages
                .filter { $0.role != .system }
                .dropLast(4) // Keep recent 4 messages out of summary
                .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
                .joined(separator: "\n")

            if !messagesToSummarize.isEmpty {
                isSummarizing = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    defer { self.isSummarizing = false }
                    await self.summarizeOldMessages(messagesToSummarize)
                }
            }
        }

        // Priority-based trimming
        let maxIterations = messages.count
        var iterations = 0
        var removedThisPass = 0

        while tokenCount > TokenBudget.maxHistoryTokens && messages.count > 3 && iterations < maxIterations {
            iterations += 1

            // Find lowest priority message to remove (skip system messages and last 2)
            // Priority: system (never) > tool (highest) > assistant > user (lowest)
            if let index = findLowestPriorityMessage() {
                let removed = messages.remove(at: index)
                tokenCount -= TokenBudget.estimate(removed.content)
                removedThisPass += 1
            } else {
                break
            }
        }

        // Track cumulative trimmed count
        trimmedCount += removedThisPass
        if removedThisPass > 0 {
            ClarissaLogger.agent.info("Trimmed \(removedThisPass) messages (priority-based), total trimmed: \(self.trimmedCount)")
        }

        if iterations >= maxIterations {
            ClarissaLogger.agent.warning("Token trimming reached max iterations, stopping to prevent infinite loop")
        }
    }

    /// Find the index of the lowest priority non-system message to trim
    /// Prefers removing older user messages first, then assistant, then tool results
    /// Always keeps the last 2 non-system messages
    private func findLowestPriorityMessage() -> Int? {
        let nonSystemIndices = messages.indices.filter { messages[$0].role != .system }
        // Keep at least the last 2 non-system messages
        let trimmable = nonSystemIndices.dropLast(2)
        guard !trimmable.isEmpty else { return nil }

        // Find first user message (lowest priority)
        if let idx = trimmable.first(where: { messages[$0].role == .user }) {
            return idx
        }
        // Then assistant messages
        if let idx = trimmable.first(where: { messages[$0].role == .assistant }) {
            return idx
        }
        // Then tool messages (highest priority among trimmable)
        if let idx = trimmable.first(where: { messages[$0].role == .tool }) {
            return idx
        }
        return nil
    }

    /// Summarize older conversation messages for context preservation
    private func summarizeOldMessages(_ text: String) async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            do {
                let model = SystemLanguageModel()
                let session = LanguageModelSession(
                    model: model,
                    instructions: Instructions("""
                    Summarize this conversation in 2-3 sentences.
                    Focus on key topics, decisions, and facts mentioned.
                    Be concise and factual.
                    """)
                )

                let response = try await session.respond(to: Prompt(text))
                // Limit summary to stay within token budget
                let summary = String(response.content.prefix(500))
                conversationSummary = summary
                ClarissaLogger.agent.info("Created conversation summary (\(summary.count) chars)")
            } catch {
                ClarissaLogger.agent.error("Failed to create conversation summary: \(error.localizedDescription)")
            }
        }
        #endif
    }

    /// Run the agent with a user message
    /// - Parameters:
    ///   - userMessage: The text content of the user's message
    ///   - imageData: Optional thumbnail image data to persist with the message
    public func run(_ userMessage: String, imageData: Data? = nil) async throws -> String {
        ClarissaLogger.agent.info("Starting agent run with message: \(userMessage.prefix(50), privacy: .public)...")

        guard let provider = provider else {
            ClarissaLogger.agent.error("No provider configured")
            throw AgentError.noProvider
        }

        await AnalyticsCollector.shared.beginSession()

        // Clear template after its initial message has been processed.
        // The template's system prompt focus and tool prefetch only apply to the first
        // message — subsequent messages should behave normally with all tools available.
        if templatePrefetchDone, currentTemplate != nil {
            ClarissaLogger.agent.info("Clearing template after initial message")
            applyTemplate(nil)
        }

        // Template prefetch: when a template specifies required tools, prefetch their data
        // so the model doesn't need to decide which tools to call — data is already available.
        // This runs regardless of ProactiveContext setting since templates explicitly declare tools.
        var proactiveData: String?
        var prefetchedToolNames: Set<String> = []
        var isTemplatePrefetch = false
        if let template = currentTemplate, let requiredTools = template.toolNames, !requiredTools.isEmpty, !templatePrefetchDone {
            if let result = await prefetchTemplateTools(requiredTools) {
                proactiveData = result.context
                prefetchedToolNames = result.fetchedTools
                isTemplatePrefetch = true
                callbacks?.onProactiveContext(labels: requiredTools)
                ClarissaLogger.agent.info("Template prefetch completed for: \(requiredTools)")
            }
            templatePrefetchDone = true
        }

        // Proactive context: detect intents and prefetch data in parallel with prompt building
        // Only when FM is active (free, on-device) and user opted in
        // Skip if template prefetch already provided data
        if proactiveData == nil && ProactiveContext.isEnabled && provider.handlesToolsNatively {
            let intents = ProactiveContext.detectIntents(in: userMessage)
            if !intents.isEmpty {
                proactiveData = await ProactiveContext.prefetch(intents: intents, toolRegistry: toolRegistry)
                // Track which tools were proactively prefetched so they're excluded
                // from the session — otherwise the on-device model redundantly calls
                // them again despite the data already being in the system prompt.
                prefetchedToolNames = Set(intents.map(\.toolName))
                let labels = intents.map(\.label)
                callbacks?.onProactiveContext(labels: labels)
            }
        }

        // Build system prompt with budget-tracked sections (proactive context included)
        let systemPrompt = await buildSystemPrompt(proactiveContext: proactiveData)

        if messages.isEmpty || messages.first?.role != .system {
            messages.insert(.system(systemPrompt), at: 0)
        } else {
            messages[0] = .system(systemPrompt)
        }

        // Add user message with optional image
        messages.append(.user(userMessage, imageData: imageData))

        // Trim history to fit within Foundation Models context window
        trimHistoryIfNeeded()

        // Get available tools (limited by provider capability)
        // For providers that handle tools natively (e.g., Foundation Models),
        // we still pass tool definitions but they're used by the session internally.
        var tools: [ToolDefinition]
        if isTemplatePrefetch {
            // Template prefetch: ALL needed data is in the system prompt and the template
            // instructs "Do NOT call tools again" — register NO tools. Otherwise the
            // on-device model aggressively calls unrelated tools (e.g. calculator during
            // a morning briefing) producing hallucinated results.
            tools = []
        } else {
            tools = toolRegistry.getDefinitionsLimited(provider.maxTools)
            // Proactive prefetch: exclude only the prefetched tools so the model doesn't
            // redundantly re-call them, but keep other tools available since the user
            // message may need them (e.g. "What's the weather and set a reminder").
            if !prefetchedToolNames.isEmpty {
                tools = tools.filter { !prefetchedToolNames.contains($0.name) }
            }
        }

        // Skip tools entirely for conversational queries (greetings, capability questions, etc.)
        // The on-device Foundation Model aggressively calls tools even when they're not needed.
        // Since native tool handling auto-executes tools with no interception point, the only
        // reliable fix is to not register tools for queries that clearly don't need them.
        if ToolCallValidator.isConversational(userMessage) {
            ClarissaLogger.agent.info("Conversational query detected — skipping tools")
            tools = []
        }

        // Intent-based tool restriction: when a message clearly targets one tool,
        // restrict the session to just that tool. This prevents the model from
        // calling unrelated tools (e.g., weather for "9*8") which causes wrong
        // responses and unnecessary network requests.
        if !tools.isEmpty,
           let restrictedName = ToolCallValidator.restrictedToolName(for: userMessage) {
            let filtered = tools.filter { $0.name == restrictedName }
            if !filtered.isEmpty {
                ClarissaLogger.agent.info("Intent-based restriction: using only '\(restrictedName)' tool")
                tools = filtered
            } else {
                // The intended tool isn't available (disabled or at max-tools limit).
                // For math queries, fall back to the local evaluator immediately
                // rather than passing all tools and risking a wrong-tool call.
                if restrictedName == "calculator",
                   let fallback = ToolCallValidator.attemptMathFallbackPublic(from: userMessage) {
                    ClarissaLogger.agent.info("Calculator not available — using local math fallback")
                    let assistantMessage = Message.assistant(fallback)
                    messages.append(assistantMessage)
                    callbacks?.onStreamChunk(chunk: fallback)
                    callbacks?.onResponse(content: fallback)
                    return fallback
                }
                // The intended tool is unavailable — strip all tools rather than letting
                // the on-device model call unrelated tools (e.g., calendar for a reminder
                // query). The model will answer from its own knowledge instead.
                ClarissaLogger.agent.warning("Intent restriction for '\(restrictedName)' found no matching tool — stripping all tools")
                tools = []
            }
        }

        // Creative writing bypass: open-ended generative prompts (stories, poems, etc.)
        // can trigger Foundation Models safety guardrails which SIGKILL the process.
        // Handle these locally without ever sending to the FM session.
        if provider.handlesToolsNatively && ToolCallValidator.isCreativeWriting(userMessage) {
            ClarissaLogger.agent.info("Creative writing detected — handling locally to avoid guardrail kill")
            let response = ToolCallValidator.creativeWritingResponse
            let assistantMessage = Message.assistant(response)
            messages.append(assistantMessage)
            callbacks?.onStreamChunk(chunk: response)
            callbacks?.onResponse(content: response)
            return response
        }

        // Check if provider handles tools natively (e.g., Apple Foundation Models)
        // Native providers execute tools within the LLM session - no manual execution needed
        let nativeToolHandling = provider.handlesToolsNatively
        if nativeToolHandling {
            ClarissaLogger.agent.info("Using native tool handling (tools executed within LLM session)")
        }

        // ReAct loop
        // For native tool providers, this typically completes in one iteration
        // since tools are executed internally by the LLM session
        var recentToolCalls: [String] = []  // Track recent tool calls for loop detection
        for _ in 0..<config.maxIterations {
            await AnalyticsCollector.shared.recordReactIteration()
            callbacks?.onThinking()

            // Get LLM response with streaming (with retry for rate limits)
            var fullContent = ""
            var toolCalls: [ToolCall] = []
            var toolExecutions: [ToolExecution] = []
            var lastError: Error?

            // Retry loop for transient errors like rate limiting
            for attempt in 0..<config.maxRetries {
                do {
                    fullContent = ""
                    toolCalls = []
                    toolExecutions = []

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
                        // Collect tool executions from native providers
                        if let executions = chunk.toolExecutions {
                            toolExecutions.append(contentsOf: executions)
                        }
                    }
                    // Success - break out of retry loop
                    lastError = nil
                    break
                } catch {
                    lastError = error

                    // Check if error is retryable
                    if RetryHelper.isRetryable(error) && attempt < self.config.maxRetries - 1 {
                        let delay = RetryHelper.delay(forAttempt: attempt, baseDelay: self.config.baseRetryDelay)
                        ClarissaLogger.agent.info("Rate limited, retrying in \(delay)s (attempt \(attempt + 1)/\(self.config.maxRetries))")
                        try await Task.sleep(for: .seconds(delay))
                        continue
                    }
                    await AnalyticsCollector.shared.completeSession(crashed: true)
                    throw error
                }
            }

            // If we exhausted retries, throw the last error
            if let error = lastError {
                await AnalyticsCollector.shared.completeSession(crashed: true)
                throw error
            }

            // Create assistant message
            let assistantMessage = Message.assistant(
                fullContent,
                toolCalls: toolCalls.isEmpty ? nil : toolCalls
            )
            // For providers with native tool handling, skip manual tool execution
            // The LLM session has already executed tools and incorporated results
            // Fire callbacks for any tool executions so UI can display tool result cards
            if nativeToolHandling {
                // Add tool messages BEFORE assistant message to maintain correct order
                // This matches the UI display order: tool card appears before response
                for execution in toolExecutions {
                    callbacks?.onToolCall(name: execution.name, arguments: execution.arguments)
                    callbacks?.onToolResult(name: execution.name, result: execution.result, success: execution.success)
                    await AnalyticsCollector.shared.recordToolCall(name: execution.name, success: execution.success)

                    // Add tool message to history so it gets saved
                    let toolMessage = Message.tool(
                        callId: UUID().uuidString,
                        name: execution.name,
                        content: execution.result
                    )
                    messages.append(toolMessage)
                }

                // Add assistant message after tool messages
                messages.append(assistantMessage)

                ClarissaLogger.agent.info("Agent run completed (native tool handling, \(toolExecutions.count) tools executed)")
                var finalContent = Self.applyRefusalFallback(fullContent, userMessage: userMessage)

                // Validate response coherence — catch hallucinated actions and wrong-tool responses
                let execTuples = toolExecutions.map { (name: $0.name, result: $0.result) }
                if let corrected = ToolCallValidator.checkCoherence(
                    userMessage: userMessage,
                    response: finalContent,
                    toolExecutions: execTuples
                ) {
                    ClarissaLogger.agent.warning("Response coherence check failed, using corrected response")
                    finalContent = corrected
                    // Replace the last assistant message with the corrected one
                    if let lastIdx = messages.lastIndex(where: { $0.role == .assistant }) {
                        messages[lastIdx] = .assistant(corrected)
                    }
                }

                callbacks?.onResponse(content: finalContent)
                let stats = getContextStats()
                await AnalyticsCollector.shared.recordContextUsage(percent: stats.usagePercent)
                await AnalyticsCollector.shared.completeSession(crashed: false)
                return finalContent
            }

            // For non-native providers, add assistant message first
            messages.append(assistantMessage)

            // Check for tool calls (only for non-native providers like OpenRouter)
            if !toolCalls.isEmpty {
                for toolCall in toolCalls {
                    // Validate tool selection before execution
                    if let mismatch = ToolCallValidator.detectMismatch(userMessage: userMessage, toolName: toolCall.name) {
                        ClarissaLogger.agent.warning("Tool mismatch detected: \(mismatch, privacy: .public)")
                        // Tell the model to pick the correct tool instead of executing the wrong one
                        let errorResult = Self.encodeErrorJSON(
                            "Wrong tool selected. \(mismatch). Re-read the user's message and pick the correct tool.",
                            suggestion: "Use the calculator tool for math questions"
                        )
                        let toolMessage = Message.tool(callId: toolCall.id, name: toolCall.name, content: errorResult)
                        messages.append(toolMessage)
                        callbacks?.onToolCall(name: toolCall.name, arguments: toolCall.arguments)
                        callbacks?.onToolResult(name: toolCall.name, result: errorResult, success: false)
                        continue
                    }

                    callbacks?.onToolCall(name: toolCall.name, arguments: toolCall.arguments)

                    // Execute tool
                    do {
                        ClarissaLogger.tools.info("Executing tool: \(toolCall.name, privacy: .public)")
                        let result = try await toolRegistry.execute(name: toolCall.name, arguments: toolCall.arguments)
                        let toolMessage = Message.tool(callId: toolCall.id, name: toolCall.name, content: result)
                        messages.append(toolMessage)
                        callbacks?.onToolResult(name: toolCall.name, result: result, success: true)
                        await AnalyticsCollector.shared.recordToolCall(name: toolCall.name, success: true)
                        ClarissaLogger.tools.info("Tool \(toolCall.name, privacy: .public) completed successfully")
                    } catch {
                        ClarissaLogger.tools.error("Tool \(toolCall.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        // Include a recovery suggestion to help the model provide useful feedback
                        let suggestion = Self.getSuggestion(for: toolCall.name, error: error)
                        let errorResult = Self.encodeErrorJSON(error.localizedDescription, suggestion: suggestion)
                        let toolMessage = Message.tool(callId: toolCall.id, name: toolCall.name, content: errorResult)
                        messages.append(toolMessage)
                        callbacks?.onToolResult(name: toolCall.name, result: errorResult, success: false)
                        await AnalyticsCollector.shared.recordToolCall(name: toolCall.name, success: false)
                    }
                }

                // Detect infinite tool-call loops: if the same tool+args pattern repeats 3 times, break
                let callSignature = toolCalls.map { "\($0.name):\($0.arguments)" }.joined(separator: "|")
                recentToolCalls.append(callSignature)
                if recentToolCalls.count >= 3 {
                    let last3 = recentToolCalls.suffix(3)
                    if Set(last3).count == 1 {
                        ClarissaLogger.agent.warning("Detected repeated tool call loop, breaking out")
                        let loopMsg = "I seem to be stuck in a loop. Let me try a different approach or answer directly."
                        callbacks?.onResponse(content: loopMsg)
                        messages.append(.assistant(loopMsg))
                        await AnalyticsCollector.shared.completeSession(crashed: false)
                        return loopMsg
                    }
                }

                continue // Continue loop for next response
            }

            // No tool calls - final response
            ClarissaLogger.agent.info("Agent run completed with response")
            var finalContent = Self.applyRefusalFallback(fullContent, userMessage: userMessage)

            // Validate response coherence (no tools were called, so pass empty executions)
            if let corrected = ToolCallValidator.checkCoherence(
                userMessage: userMessage,
                response: finalContent,
                toolExecutions: []
            ) {
                ClarissaLogger.agent.warning("Response coherence check failed (no-tool path), using corrected response")
                finalContent = corrected
                // Update the message in history
                if let lastIdx = messages.lastIndex(where: { $0.role == .assistant }) {
                    messages[lastIdx] = .assistant(corrected)
                }
            }

            callbacks?.onResponse(content: finalContent)
            let stats = getContextStats()
            await AnalyticsCollector.shared.recordContextUsage(percent: stats.usagePercent)
            await AnalyticsCollector.shared.completeSession(crashed: false)
            return finalContent
        }

        ClarissaLogger.agent.warning("Agent reached max iterations")
        await AnalyticsCollector.shared.completeSession(crashed: true)
        throw AgentError.maxIterationsReached
    }

    // MARK: - Refusal Detection

    /// Phrases that indicate the model is refusing a request
    private static let refusalPhrases = [
        "i cannot fulfill",
        "i can't fulfill",
        "i'm not able to",
        "i am not able to",
        "i cannot help with",
        "i can't help with",
        "i'm unable to",
        "i am unable to",
        "i cannot assist",
        "i can't assist",
        "sorry, but i cannot",
        "sorry, but i can't",
        "i'm sorry, but i cannot",
        "i'm sorry, but i can't"
    ]

    /// Context-aware suggestions based on what the user was trying to do
    private static func getRefusalSuggestion(for userMessage: String) -> String {
        let lowercased = userMessage.lowercased()

        // Detect intent and suggest relevant alternatives
        if lowercased.contains("weather") || lowercased.contains("temperature") || lowercased.contains("forecast") {
            return "I can check the weather for you. Try asking \"What's the weather in [city]?\" or just \"Weather?\""
        }
        if lowercased.contains("remind") || lowercased.contains("reminder") || lowercased.contains("task") {
            return "I can help with reminders. Try \"Remind me to [task]\" or \"Show my reminders\"."
        }
        if lowercased.contains("calendar") || lowercased.contains("meeting") || lowercased.contains("schedule") || lowercased.contains("event") {
            return "I can help with your calendar. Try \"What's on my calendar?\" or \"Schedule a meeting\"."
        }
        if lowercased.contains("calculate") || lowercased.contains("math") || lowercased.contains("%") || lowercased.contains("tip") {
            return "I can do calculations. Try \"What's 20% of 85?\" or \"Calculate 15 + 27\"."
        }
        if lowercased.contains("contact") || lowercased.contains("phone") || lowercased.contains("email") || lowercased.contains("call") {
            return "I can look up contacts. Try \"What's [name]'s phone number?\" or \"Find [name]'s email\"."
        }

        // Default fallback
        return "I'm best at helping with your calendar, reminders, weather, calculations, and contacts. What can I help you with?"
    }

    /// Check if a response is a refusal and provide a context-aware redirect if so
    private static func applyRefusalFallback(_ content: String, userMessage: String) -> String {
        let lowercased = content.lowercased()

        for phrase in refusalPhrases {
            if lowercased.contains(phrase) {
                ClarissaLogger.agent.info("Detected refusal response, applying context-aware fallback")
                return getRefusalSuggestion(for: userMessage)
            }
        }

        return content
    }
    
    /// Aggressively trim conversation to recover from contextWindowExceeded
    /// Keeps only the system message and last 2 non-system messages, forcing summarization
    /// - Returns: true if trimming was performed
    @discardableResult
    func aggressiveTrim() async -> Bool {
        let nonSystemMessages = messages.filter { $0.role != .system }
        guard nonSystemMessages.count > 2 else { return false }

        // Force summarize everything except the last 2 messages
        let messagesToSummarize = nonSystemMessages.dropLast(2)
            .map { "\($0.role == .user ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")

        if !messagesToSummarize.isEmpty && !isSummarizing {
            isSummarizing = true
            await summarizeOldMessages(messagesToSummarize)
            isSummarizing = false
        }

        // Keep system + last 2 non-system messages
        let systemMessage = messages.first { $0.role == .system }
        let lastTwo = Array(nonSystemMessages.suffix(2))
        let removedCount = messages.count - (systemMessage != nil ? 1 : 0) - lastTwo.count
        messages = (systemMessage.map { [$0] } ?? []) + lastTwo
        trimmedCount += removedCount

        // Reset provider session to clear cached transcript
        await provider?.resetSession()

        ClarissaLogger.agent.info("Aggressive trim: removed \(removedCount) messages, summary created: \(self.conversationSummary != nil)")
        return true
    }

    /// Reset conversation (keep system prompt)
    /// Note: This only clears local message history. Call resetForNewConversation()
    /// to also reset the LLM provider session.
    func reset() {
        let systemMessage = messages.first { $0.role == .system }
        messages = systemMessage.map { [$0] } ?? []
        trimmedCount = 0
        conversationSummary = nil
        isSummarizing = false
        templatePrefetchDone = false
        // Reset native tool usage tracking
        NativeToolUsageTracker.shared.reset()
    }

    /// Reset for a completely new conversation
    /// This clears both local message history AND the LLM provider's session
    /// to prevent context bleeding between conversations
    func resetForNewConversation() async {
        reset()
        // Also reset the provider session to clear any cached transcript
        await provider?.resetSession()
        // Reset native tool usage tracking for accurate context stats
        NativeToolUsageTracker.shared.reset()
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

        // Include tool tokens from native Foundation Models tool calls
        // These are tracked separately since FM handles tools opaquely
        toolTokens += NativeToolUsageTracker.shared.totalToolTokens

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

