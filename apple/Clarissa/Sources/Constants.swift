import Foundation

/// Application-wide constants
enum ClarissaConstants {

    // MARK: - Agent Configuration

    /// Default maximum iterations for the ReAct loop
    static let defaultMaxIterations = 10

    // MARK: - Session Management

    /// Maximum number of messages to keep per session
    static let maxMessagesPerSession = 100

    /// Maximum number of sessions to keep in history
    static let maxSessions = 50

    // MARK: - UI Layout

    /// Maximum width for message bubbles on larger screens (iPad/Mac)
    static let maxMessageBubbleWidth: CGFloat = 600

    /// Minimum spacing for message bubble margins
    static let messageBubbleMinSpacing: CGFloat = 60

    /// Corner radius for message bubbles
    static let messageBubbleCornerRadius: CGFloat = 18

    /// Corner radius for tool status badges
    static let toolStatusCornerRadius: CGFloat = 12

    // MARK: - Animation

    /// Duration for message entrance animations
    static let messageAnimationDuration: Double = 0.25

    /// Duration for cursor blink animation
    static let cursorBlinkDuration: Double = 0.5

    // MARK: - Networking

    /// Default timeout for network requests (seconds)
    static let networkTimeoutSeconds: TimeInterval = 30

    /// Extended timeout for LLM API requests (seconds)
    /// Cloud APIs may take longer due to model inference time
    static let llmApiTimeoutSeconds: TimeInterval = 120

    /// OpenRouter API base URL
    static let openRouterBaseURL = "https://openrouter.ai/api/v1"

    /// OpenRouter completions endpoint path
    static let openRouterCompletionsPath = "/chat/completions"

    /// Maximum allowed response size for web fetch (5MB)
    static let maxWebFetchResponseSize = 5 * 1024 * 1024

    /// Default maximum response length for web fetch
    static let defaultMaxWebFetchLength = 10000

    // MARK: - Token Budget (Foundation Models)

    /// Total context window for Foundation Models (Apple Intelligence)
    /// Note: The 4,096 token limit is for input + output combined, not separate
    static let foundationModelsContextWindow = 4096

    /// Reserve tokens for system instructions (increased for few-shot examples)
    static let tokenSystemReserve = 500

    /// Reserve tokens for tool schemas (~100 per tool with @Generable)
    static let tokenToolSchemaReserve = 400

    /// Reserve tokens for the expected response
    static let tokenResponseReserve = 1200

    // MARK: - Foundation Models Generation Options

    /// Temperature for Foundation Models (0.0-1.0)
    /// Lower = more focused/deterministic, Higher = more creative/random
    /// 0.4 is good for tool-calling tasks that need consistency
    static let foundationModelsTemperature: Double = 0.4

    /// Maximum response tokens for Foundation Models
    /// Keeps responses concise for mobile UI while leaving room for tool results
    static let foundationModelsMaxResponseTokens: Int = 400

    // MARK: - Session Count Badge

    /// Maximum session count to display (shows "99+" for higher)
    static let maxDisplayedSessionCount = 99
}

// MARK: - macOS Menu Command Notifications

#if os(macOS)
public extension Notification.Name {
    /// Posted when user requests a new conversation via menu/shortcut
    static let newConversation = Notification.Name("clarissa.newConversation")

    /// Posted when user requests to clear the conversation via menu/shortcut
    static let clearConversation = Notification.Name("clarissa.clearConversation")

    /// Posted when user requests to show the about window
    static let showAbout = Notification.Name("clarissa.showAbout")

    /// Posted when user toggles voice input via menu/shortcut
    static let toggleVoiceInput = Notification.Name("clarissa.toggleVoiceInput")

    /// Posted when user requests to read the last response aloud
    static let speakLastResponse = Notification.Name("clarissa.speakLastResponse")

    /// Posted when user stops speech playback
    static let stopSpeaking = Notification.Name("clarissa.stopSpeaking")
}
#endif

