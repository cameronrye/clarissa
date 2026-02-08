import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    /// Shared singleton instance - use this in production code
    /// Note: Direct init() is intentionally public for SwiftUI previews
    public static let shared = AppState()

    /// Whether the app is running in screenshot/demo mode for App Store screenshots
    public var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-SCREENSHOT_MODE")
    }

    @Published public var isOnboardingComplete: Bool
    @Published public var selectedProvider: LLMProviderType {
        didSet {
            // Persist provider selection
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: Self.providerKey)
        }
    }

    // MARK: - Shortcut & URL Scheme Integration

    /// Pending question from Siri Shortcut or URL scheme
    @Published public var pendingShortcutQuestion: String?

    /// Request to start a new conversation (from Shortcut or URL)
    @Published public var requestNewConversation: Bool = false

    /// Request to start voice mode (from Shortcut)
    @Published public var requestVoiceMode: Bool = false

    /// Pending template ID from Siri Shortcut (triggers template start on next configure)
    @Published public var pendingTemplateId: String?

    /// Source of the pending question for analytics/logging
    @Published public var pendingQuestionSource: QuestionSource = .direct

    private static let providerKey = "selectedProviderType"

    public init() {
        // In screenshot mode, always skip onboarding
        if ProcessInfo.processInfo.arguments.contains("-SCREENSHOT_MODE") {
            self.isOnboardingComplete = true
        } else {
            self.isOnboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
        }

        // Load persisted provider selection with fallback to default
        if let savedRaw = UserDefaults.standard.string(forKey: Self.providerKey),
           let savedProvider = LLMProviderType(rawValue: savedRaw) {
            self.selectedProvider = savedProvider
        } else {
            self.selectedProvider = .foundationModels
        }
    }

    // MARK: - URL Scheme Handling

    /// Handle incoming URL scheme (clarissa://...)
    /// Supported URLs:
    /// - clarissa://ask?q=<question> - Ask a question
    /// - clarissa://ask?q=<question>&new=true - Start new conversation and ask
    /// - clarissa://new - Start a new conversation
    /// - clarissa://voice - Start voice mode
    /// - clarissa://memory?action=sync - Trigger memory sync from CLI
    public func handleURL(_ url: URL) {
        guard url.scheme == "clarissa" else { return }

        let host = url.host ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        switch host {
        case "ask":
            // Handle ask command: clarissa://ask?q=<question>&new=<bool>
            if let question = queryItems.first(where: { $0.name == "q" })?.value,
               !question.isEmpty {
                // Check if we should start a new conversation first
                if queryItems.first(where: { $0.name == "new" })?.value == "true" {
                    requestNewConversation = true
                }
                pendingShortcutQuestion = question
                pendingQuestionSource = .urlScheme
            }

        case "new":
            // Handle new conversation: clarissa://new
            requestNewConversation = true
            pendingQuestionSource = .urlScheme

        case "voice":
            // Handle voice mode: clarissa://voice
            requestVoiceMode = true
            pendingQuestionSource = .urlScheme

        case "template":
            // Handle template start: clarissa://template?id=morning_briefing
            if let templateId = queryItems.first(where: { $0.name == "id" })?.value,
               !templateId.isEmpty {
                pendingTemplateId = templateId
                pendingQuestionSource = .urlScheme
            }

        case "memory":
            // Handle memory commands: clarissa://memory?action=sync
            if queryItems.first(where: { $0.name == "action" })?.value == "sync" {
                Task {
                    // Force reload memories from shared CLI file
                    await MemoryManager.shared.reload()
                }
            }

        default:
            // Unknown command, try treating the whole path as a question
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                requestNewConversation = true
                pendingShortcutQuestion = path
                pendingQuestionSource = .urlScheme
            }
        }
    }

    public func completeOnboarding() {
        isOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }

    public func resetOnboarding() {
        isOnboardingComplete = false
        UserDefaults.standard.set(false, forKey: "onboardingComplete")
    }

    /// Set provider with availability fallback
    /// If the requested provider is not available, falls back to an available one
    public func setProviderWithFallback(_ provider: LLMProviderType, availabilityCheck: (LLMProviderType) async -> Bool) async {
        if await availabilityCheck(provider) {
            selectedProvider = provider
        } else {
            // Try fallback to other provider
            for fallback in LLMProviderType.allCases where fallback != provider {
                if await availabilityCheck(fallback) {
                    selectedProvider = fallback
                    return
                }
            }
            // If nothing is available, keep the selected one anyway
            // (the provider setup will handle showing an appropriate error)
            selectedProvider = provider
        }
    }
}

public enum LLMProviderType: String, CaseIterable, Identifiable, Sendable {
    case foundationModels = "On-Device (Apple Intelligence)"
    case openRouter = "OpenRouter (Cloud)"

    public var id: String { rawValue }
}

/// Source of a pending question
public enum QuestionSource: Sendable {
    /// Direct input in the app
    case direct
    /// From Siri Shortcut
    case siriShortcut
    /// From URL scheme (CLI integration)
    case urlScheme
    /// From a notification action
    case notification
}

