import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Provider using Apple's on-device Foundation Models with native tool calling
/// Note: This class is @MainActor isolated to ensure thread-safe access to mutable state
/// The @preconcurrency conformance allows the protocol methods to safely cross actor boundaries
@available(iOS 26.0, macOS 26.0, *)
@MainActor
public final class FoundationModelsProvider: @preconcurrency LLMProvider {
    /// Provider name - nonisolated for Sendable protocol conformance
    public nonisolated let name = "Apple Intelligence"

    /// Maximum tools per session (Guide recommends 3-5 max) - nonisolated for Sendable
    public nonisolated let maxTools = maxToolsForFoundationModels

    /// Foundation Models handles tools natively within the LanguageModelSession
    /// Tools are executed automatically and results are incorporated into the response
    public nonisolated let handlesToolsNatively = true

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    private var currentInstructions: String?
    #endif

    /// Access to the tool registry for native tool calling
    private let toolRegistry: ToolRegistry

    /// Track which tools were used to create the current session
    /// Session is invalidated if this changes (e.g., user enables/disables tools)
    private var currentToolSet: Set<String>?

    /// Prevents concurrent respond() calls which cause crashes
    /// Community insight: "Don't call respond(to:) on a session again before it returns - this causes a crash"
    private var isProcessing = false

    public init(toolRegistry: ToolRegistry = .shared) {
        self.toolRegistry = toolRegistry
    }

    public var isAvailable: Bool {
        get async {
            #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available:
                return true
            case .unavailable(_):
                return false
            @unknown default:
                return false
            }
            #else
            return false
            #endif
        }
    }

    /// Get detailed availability status for UI feedback
    var availabilityStatus: FoundationModelsAvailability {
        get async {
            #if canImport(FoundationModels)
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled):
                return .appleIntelligenceNotEnabled
            case .unavailable(.modelNotReady):
                return .modelNotReady
            case .unavailable(_):
                return .unavailable
            @unknown default:
                return .unavailable
            }
            #else
            return .unavailable
            #endif
        }
    }

    #if canImport(FoundationModels)
    /// Create or reuse session with native tool support
    /// Tools are registered directly with LanguageModelSession for native tool calling
    /// - Parameter systemPrompt: The system prompt/instructions for the session
    /// - Parameter withTools: Whether to include tools from the registry (false for simple text generation)
    @MainActor
    private func getOrCreateSession(systemPrompt: String?, withTools: Bool = true) -> LanguageModelSession {
        let instructionsText = systemPrompt ?? "You are Clarissa, a helpful AI assistant."

        // Use permissive guardrails for the memory feature to work correctly.
        // The app allows users to save personal facts (e.g., "My name is Cameron", "I prefer dark mode")
        // which are stored in the system prompt. Without permissive guardrails, the model may refuse
        // to recall these user-provided facts, breaking the core memory functionality.
        // This setting only affects content transformations, not safety guardrails.
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

        // For tool-less sessions (e.g., prompt enhancement), always create fresh
        // This prevents pollution from previous chat sessions and ensures clean context
        if !withTools {
            let instructions = Instructions(instructionsText)
            // Create a simple session without tools for text generation tasks
            return LanguageModelSession(model: model, instructions: instructions)
        }

        // Get current enabled tools to check if session needs refresh
        let enabledToolNames = Set(ToolSettings.shared.enabledToolNames)

        // Reuse existing session if instructions AND tools haven't changed
        // Session must be invalidated if user enables/disables tools in settings
        if let existingSession = session,
           currentInstructions == instructionsText,
           currentToolSet == enabledToolNames {
            ClarissaLogger.provider.debug("Reusing existing session - instructions unchanged")
            return existingSession
        }

        // Log why we're creating a new session
        if session == nil {
            ClarissaLogger.provider.info("Creating new session - no existing session")
        } else if currentInstructions != instructionsText {
            ClarissaLogger.provider.info("Creating new session - instructions changed (has memories: \(instructionsText.contains("Saved Facts")))")
        } else {
            ClarissaLogger.provider.info("Creating new session - tool set changed")
        }

        // Get Apple-native tools from the registry (limited to maxTools)
        let appleTools = toolRegistry.getAppleToolsLimited(maxTools)

        // Create Instructions struct as per the guide
        let instructions = Instructions(instructionsText)

        // Create session with model, tools and instructions using correct API
        let newSession = LanguageModelSession(
            model: model,
            tools: appleTools,
            instructions: instructions
        )

        session = newSession
        currentInstructions = instructionsText
        currentToolSet = enabledToolNames
        return newSession
    }

    /// Prewarm the session for faster first response
    @MainActor
    func prewarm(with promptPrefix: String? = nil) {
        let session = getOrCreateSession(systemPrompt: nil)
        if let prefix = promptPrefix {
            session.prewarm(promptPrefix: Prompt(prefix))
        } else {
            session.prewarm()
        }
    }
    #endif

    /// Stream completion - nonisolated to allow cross-actor calls from PromptEnhancer, etc.
    /// All MainActor work happens inside the Task, so this is safe to call from any context.
    public nonisolated func streamComplete(
        messages: [Message],
        tools: [ToolDefinition]
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                #if canImport(FoundationModels)
                // Prevent concurrent respond() calls - causes crash per community insights
                guard !self.isProcessing else {
                    continuation.finish(throwing: FoundationModelsError.concurrentRequests)
                    return
                }
                self.isProcessing = true
                defer { self.isProcessing = false }

                do {
                    // Check availability with detailed status
                    switch SystemLanguageModel.default.availability {
                    case .available:
                        break // Continue with generation
                    case .unavailable(.deviceNotEligible):
                        continuation.finish(throwing: FoundationModelsError.deviceNotEligible)
                        return
                    case .unavailable(.appleIntelligenceNotEnabled):
                        continuation.finish(throwing: FoundationModelsError.appleIntelligenceNotEnabled)
                        return
                    case .unavailable(.modelNotReady):
                        continuation.finish(throwing: FoundationModelsError.modelNotReady)
                        return
                    case .unavailable(_):
                        continuation.finish(throwing: FoundationModelsError.notAvailable)
                        return
                    @unknown default:
                        continuation.finish(throwing: FoundationModelsError.notAvailable)
                        return
                    }

                    // Extract system prompt
                    let systemPrompt = messages.first { $0.role == .system }?.content

                    // Determine if this is a simple text generation request (no tools)
                    // For such requests, create a fresh tool-less session to avoid polluting
                    // the main chat session and to ensure clean context for tasks like prompt enhancement
                    let useTools = !tools.isEmpty

                    // Get or create session (tool-less sessions are always fresh)
                    let session = getOrCreateSession(systemPrompt: systemPrompt, withTools: useTools)

                    // Build the user prompt from messages
                    let promptText = buildPrompt(from: messages)

                    // Create Prompt struct as per the guide
                    let prompt = Prompt(promptText)

                    // Configure generation options for more focused responses
                    // Lower temperature = more deterministic, better for tool selection
                    // Limited response tokens = concise responses for mobile UI
                    let options = GenerationOptions(
                        temperature: ClarissaConstants.foundationModelsTemperature,
                        maximumResponseTokens: ClarissaConstants.foundationModelsMaxResponseTokens
                    )

                    // Check for cancellation before starting stream
                    try Task.checkCancellation()

                    // Stream response using correct API: streamResponse(to: Prompt, options:)
                    // The stream yields ResponseStream.Snapshot with .content property
                    let stream = session.streamResponse(to: prompt, options: options)
                    var lastContent = ""

                    for try await snapshot in stream {
                        // Check for cancellation during streaming
                        try Task.checkCancellation()

                        // Snapshot contains accumulated content - compute delta
                        // Filter out the literal "null" string which the model sometimes outputs
                        // when confused about tool calling (known Apple Intelligence quirk)
                        var currentContent = snapshot.content
                        if currentContent == "null" {
                            currentContent = ""
                        }
                        if currentContent.count > lastContent.count {
                            let delta = String(currentContent.dropFirst(lastContent.count))
                            continuation.yield(StreamChunk(
                                content: delta,
                                toolCalls: nil,
                                isComplete: false
                            ))
                        }
                        lastContent = currentContent
                    }

                    // Complete - no manual tool handling needed
                    continuation.yield(StreamChunk(
                        content: nil,
                        toolCalls: nil,
                        isComplete: true
                    ))
                    continuation.finish()

                } catch is CancellationError {
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    // Handle specific GenerationError cases as per the guide
                    let wrappedError = handleGenerationError(error)
                    continuation.finish(throwing: wrappedError)
                } catch {
                    continuation.finish(throwing: error)
                }
                #else
                continuation.finish(throwing: FoundationModelsError.notAvailable)
                #endif
            }

            // Handle cancellation from the consumer side
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    #if canImport(FoundationModels)
    /// Handle GenerationError cases with user-friendly messages
    private func handleGenerationError(_ error: LanguageModelSession.GenerationError) -> FoundationModelsError {
        switch error {
        case .guardrailViolation(_):
            return .guardrailViolation
        case .exceededContextWindowSize(let context):
            return .contextWindowExceeded(context: "\(context)")
        case .unsupportedLanguageOrLocale(let locale):
            return .unsupportedLanguage(locale: "\(locale)")
        case .refusal(let refusal, _):
            return .refusal(reason: "\(refusal)")
        case .assetsUnavailable(_):
            return .modelNotReady
        case .rateLimited(_):
            return .rateLimited
        case .concurrentRequests(_):
            return .concurrentRequests
        case .unsupportedGuide(_):
            return .generationFailed("Unsupported guide configuration")
        case .decodingFailure(_):
            return .generationFailed("Failed to decode response")
        @unknown default:
            return .generationFailed(error.localizedDescription)
        }
    }
    #endif

    private func buildPrompt(from messages: [Message]) -> String {
        // For Foundation Models with session reuse, just send the latest user message
        // The session maintains its own conversation transcript internally
        if let lastUserMessage = messages.last(where: { $0.role == .user }) {
            return lastUserMessage.content
        }

        // Fallback: concatenate non-system messages
        return messages
            .filter { $0.role != .system }
            .map { $0.content }
            .joined(separator: "\n\n")
    }

    /// Reset the session for a new conversation
    /// Clears the cached LanguageModelSession to prevent context bleeding between conversations
    public func resetSession() async {
        #if canImport(FoundationModels)
        session = nil
        currentInstructions = nil
        currentToolSet = nil
        ClarissaLogger.provider.info("Foundation Models session reset for new conversation")
        #endif
    }
}

// MARK: - Availability Status

/// Detailed availability status for UI feedback
enum FoundationModelsAvailability {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unavailable

    var userMessage: String {
        switch self {
        case .available:
            return "Apple Intelligence is ready"
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence. Requires iPhone 15 Pro or later, or M-series Mac."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled. Please enable it in Settings > Apple Intelligence & Siri."
        case .modelNotReady:
            return "Apple Intelligence is still downloading. Please wait and try again."
        case .unavailable:
            return "Apple Intelligence is not available."
        }
    }
}

// MARK: - Error Types

enum FoundationModelsError: LocalizedError {
    case notAvailable
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case toolExecutionFailed(String)
    case guardrailViolation
    case refusal(reason: String)
    case contextWindowExceeded(context: String)
    case unsupportedLanguage(locale: String)
    case rateLimited
    case concurrentRequests
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Apple Intelligence is not available on this device."
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence. Requires iPhone 15 Pro or later, or M-series Mac."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled. Please enable it in Settings > Apple Intelligence & Siri."
        case .modelNotReady:
            return "Apple Intelligence is still downloading. Please wait and try again."
        case .toolExecutionFailed(let message):
            return "Tool execution failed: \(message)"
        case .guardrailViolation:
            return "The request was blocked by safety guidelines. Please try rephrasing your question."
        case .refusal(let reason):
            return "The model declined to respond: \(reason)"
        case .contextWindowExceeded(_):
            return "The conversation is too long. Please start a new conversation."
        case .unsupportedLanguage(let locale):
            return "The language '\(locale)' is not supported. Please use English."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .concurrentRequests:
            return "Another request is in progress. Please wait for it to complete."
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        }
    }
}

