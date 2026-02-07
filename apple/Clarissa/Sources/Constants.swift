import Foundation

/// Application-wide constants
public enum ClarissaConstants {

    // MARK: - Agent Configuration

    /// Default maximum iterations for the ReAct loop
    public static let defaultMaxIterations = 10

    // MARK: - Session Management

    /// Maximum number of messages to keep per session
    public static let maxMessagesPerSession = 100

    /// Maximum number of sessions to keep in history
    public static let maxSessions = 50

    // MARK: - UI Layout

    /// Maximum width for message bubbles on larger screens (iPad/Mac)
    public static let maxMessageBubbleWidth: CGFloat = 600

    /// Minimum spacing for message bubble margins
    public static let messageBubbleMinSpacing: CGFloat = 60

    /// Corner radius for message bubbles
    public static let messageBubbleCornerRadius: CGFloat = 18

    /// Corner radius for tool status badges
    public static let toolStatusCornerRadius: CGFloat = 12

    // MARK: - Animation

    /// Duration for message entrance animations
    public static let messageAnimationDuration: Double = 0.25

    /// Duration for cursor blink animation
    public static let cursorBlinkDuration: Double = 0.5

    // MARK: - Networking

    /// Default timeout for network requests (seconds)
    public static let networkTimeoutSeconds: TimeInterval = 30

    /// Extended timeout for LLM API requests (seconds)
    /// Cloud APIs may take longer due to model inference time
    public static let llmApiTimeoutSeconds: TimeInterval = 120

    /// OpenRouter API base URL
    public static let openRouterBaseURL = "https://openrouter.ai/api/v1"

    /// OpenRouter completions endpoint path
    public static let openRouterCompletionsPath = "/chat/completions"

    /// Maximum allowed response size for web fetch (5MB)
    public static let maxWebFetchResponseSize = 5 * 1024 * 1024

    /// Default maximum response length for web fetch
    public static let defaultMaxWebFetchLength = 10000

    // MARK: - Token Budget (Foundation Models)

    /// Total context window for Foundation Models (Apple Intelligence)
    /// Note: The 4,096 token limit is for input + output combined, not separate
    public static let foundationModelsContextWindow = 4096

    /// Reserve tokens for system instructions (increased for few-shot examples)
    public static let tokenSystemReserve = 500

    /// Reserve tokens for tool schemas (~100 per tool with @Generable)
    public static let tokenToolSchemaReserve = 400

    /// Reserve tokens for the expected response
    public static let tokenResponseReserve = 1200

    // MARK: - Foundation Models Generation Options

    /// Temperature for Foundation Models (0.0-1.0)
    /// Lower = more focused/deterministic, Higher = more creative/random
    /// 0.4 is good for tool-calling tasks that need consistency
    public static let foundationModelsTemperature: Double = 0.4

    /// Maximum response tokens for Foundation Models
    /// Keeps responses concise for mobile UI while leaving room for tool results
    public static let foundationModelsMaxResponseTokens: Int = 400

    // MARK: - Session Count Badge

    /// Maximum session count to display (shows "99+" for higher)
    public static let maxDisplayedSessionCount = 99

    // MARK: - Memory Management

    /// Number of days before a memory is considered stale
    public static let memoryStaleThresholdDays = 30

    /// Similarity threshold for semantic deduplication (0.0-1.0)
    public static let memorySimilarityThreshold = 0.85

    /// Topic overlap threshold for considering memories related (0.0-1.0)
    public static let memoryTopicOverlapThreshold = 0.7

    // MARK: - System Prompt Budget (per-section caps within tokenSystemReserve)

    /// Maximum tokens for core instructions (non-negotiable base prompt)
    public static let systemBudgetCore = 250

    /// Maximum tokens for conversation summary (only if messages were trimmed)
    public static let systemBudgetSummary = 100

    /// Maximum tokens for memories injected into system prompt
    public static let systemBudgetMemories = 80

    /// Maximum tokens for proactive context (prefetched calendar/weather)
    public static let systemBudgetProactive = 80

    /// Maximum tokens for disabled tools list
    public static let systemBudgetDisabledTools = 40

    /// Maximum tokens for template focus text
    public static let systemBudgetTemplate = 50

    // MARK: - Context Summarization

    /// Percentage of context budget at which summarization triggers
    public static let summarizationThreshold = 0.8

    /// Maximum tokens reserved for the conversation summary
    public static let summaryMaxTokens = 150

    // MARK: - Siri Session

    /// Siri conversation session expiry in seconds
    public static let siriSessionExpirySeconds: TimeInterval = 300

    /// Maximum messages to keep in a Siri conversation session
    public static let siriSessionMaxMessages = 10

    // MARK: - Shared Storage

    /// Key for shared results from share extension
    public static let sharedResultsKey = "clarissa_shared_results"

    // MARK: - Accessibility

    /// Minimum touch target size for accessibility (44pt per Apple HIG)
    public static let minimumTouchTargetSize: CGFloat = 44

    /// Minimum contrast ratio for text (WCAG AA standard)
    public static let minimumContrastRatio: Double = 4.5
}

// MARK: - Cross-Platform Notifications

public extension Notification.Name {
    /// Posted when app returns to foreground to check for shared content from Share Extension
    static let checkSharedResults = Notification.Name("clarissa.checkSharedResults")
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

    /// Posted when user requests to show history view
    static let showHistory = Notification.Name("clarissa.showHistory")

    /// Posted when user requests to show settings General tab
    static let showSettingsGeneral = Notification.Name("clarissa.showSettingsGeneral")

    /// Posted when user requests to show settings Tools tab
    static let showSettingsTools = Notification.Name("clarissa.showSettingsTools")

    /// Posted when user requests to show settings Voice tab
    static let showSettingsVoice = Notification.Name("clarissa.showSettingsVoice")

    /// Posted when user requests to show settings Shortcuts tab
    static let showSettingsShortcuts = Notification.Name("clarissa.showSettingsShortcuts")

    /// Posted when user requests to show settings About tab
    static let showSettingsAbout = Notification.Name("clarissa.showSettingsAbout")
}
#endif

