import Foundation
import SwiftUI

/// View model for the chat interface
@MainActor
final class ChatViewModel: ObservableObject, AgentCallbacks {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var streamingContent: String = ""
    @Published var pendingToolConfirmation: ToolConfirmation?
    @Published var errorMessage: String?
    @Published var currentProvider: String = ""
    @Published var canCancel: Bool = false
    @Published var isSettingUpProvider: Bool = true
    @Published var showNewSessionConfirmation: Bool = false

    // MARK: - Voice Properties
    @Published var isRecording: Bool = false
    @Published var isVoiceModeActive: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var voiceTranscript: String = ""

    private var agent: Agent
    private var toolConfirmationContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private var appState: AppState?
    private var currentTask: Task<Void, Never>?
    private(set) var voiceManager: VoiceManager?

    init() {
        // Read autoApproveTools setting
        let autoApprove = UserDefaults.standard.bool(forKey: "autoApproveTools")
        let config = AgentConfig(autoApprove: autoApprove)
        self.agent = Agent(config: config)
        self.agent.callbacks = self

        // Set up provider (default to Foundation Models if available)
        Task {
            await setupProvider()
            await loadCurrentSession()
            isSettingUpProvider = false
        }

        // Initialize voice manager
        setupVoiceManager()
    }

    // MARK: - Voice Setup

    private func setupVoiceManager() {
        let manager = VoiceManager()
        self.voiceManager = manager

        // Handle transcript ready
        manager.onTranscriptReady = { [weak self] transcript in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.inputText = transcript
                self.voiceTranscript = ""

                // Auto-send in voice mode
                if self.isVoiceModeActive {
                    self.sendMessage()
                }
            }
        }

        // Observe voice manager state
        Task { @MainActor in
            for await isListening in manager.speechRecognizer.$isRecording.values {
                self.isRecording = isListening
            }
        }

        Task { @MainActor in
            for await transcript in manager.speechRecognizer.$transcript.values {
                self.voiceTranscript = transcript
                // Update input text while recording
                if self.isRecording {
                    self.inputText = transcript
                }
            }
        }

        Task { @MainActor in
            for await isSpeaking in manager.speechSynthesizer.$isSpeaking.values {
                self.isSpeaking = isSpeaking
            }
        }

        Task { @MainActor in
            for await isActive in manager.$isVoiceModeActive.values {
                self.isVoiceModeActive = isActive
            }
        }
    }

    /// Configure with AppState for provider switching
    func configure(with appState: AppState) {
        self.appState = appState
        Task {
            isSettingUpProvider = true
            await setupProvider(for: appState.selectedProvider)
            isSettingUpProvider = false
        }
    }

    /// Switch to a different provider
    func switchProvider(to providerType: LLMProviderType) async {
        isSettingUpProvider = true
        await setupProvider(for: providerType)
        isSettingUpProvider = false
    }

    private func setupProvider(for providerType: LLMProviderType? = nil) async {
        let selectedType = providerType ?? appState?.selectedProvider

        // If OpenRouter is explicitly selected, use it
        if selectedType == .openRouter {
            setupOpenRouterProvider()
            return
        }

        // Default: try Foundation Models first
        if #available(iOS 26.0, *) {
            let provider = FoundationModelsProvider()
            if await provider.isAvailable {
                agent.setProvider(provider)
                currentProvider = provider.name
                return
            }
        }

        // Fall back to OpenRouter
        setupOpenRouterProvider()
    }

    private func setupOpenRouterProvider() {
        // Get API key from Keychain (secure storage)
        let apiKey = KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? ""
        let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "anthropic/claude-sonnet-4"

        if !apiKey.isEmpty {
            let provider = OpenRouterProvider(apiKey: apiKey, model: model)
            agent.setProvider(provider)
            currentProvider = "\(provider.name) (\(formatModelName(model)))"
        } else {
            currentProvider = "No provider configured"
        }
    }

    private func formatModelName(_ model: String) -> String {
        model.components(separatedBy: "/").last ?? model
    }

    /// Refresh provider with current settings
    func refreshProvider() {
        Task {
            // Update agent config with current settings
            let autoApprove = UserDefaults.standard.bool(forKey: "autoApproveTools")
            let config = AgentConfig(autoApprove: autoApprove)
            self.agent = Agent(config: config)
            self.agent.callbacks = self

            await setupProvider(for: appState?.selectedProvider)
        }
    }
    
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        // Add user message
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        isLoading = true
        canCancel = true
        streamingContent = ""

        currentTask = Task {
            do {
                try Task.checkCancellation()
                _ = try await agent.run(text)
                // Save session after successful response
                await saveCurrentSession()
            } catch is CancellationError {
                // User cancelled - don't show error
                streamingContent = ""
            } catch {
                errorMessage = ErrorMapper.userFriendlyMessage(for: error)
            }

            isLoading = false
            canCancel = false
            streamingContent = ""
            currentTask = nil
        }
    }

    /// Cancel the current generation
    func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        canCancel = false
        streamingContent = ""
    }

    /// Retry the last user message
    func retryLastMessage() {
        // Find the last user message
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else { return }

        let lastUserMessage = messages[lastUserIndex]

        // Remove all messages after (and including) the last user message
        messages.removeSubrange(lastUserIndex...)

        // Re-send the message
        inputText = lastUserMessage.content
        sendMessage()
    }

    /// Request to start a new session (may show confirmation if messages exist)
    func requestNewSession() {
        // If there are messages, show confirmation first
        if !messages.isEmpty {
            showNewSessionConfirmation = true
        } else {
            startNewSession()
        }
    }

    /// Actually start a new session (called after confirmation or if no messages)
    func startNewSession() {
        showNewSessionConfirmation = false

        // Cancel any running task first
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        canCancel = false

        // Clear UI state immediately
        messages.removeAll()
        agent.reset()
        streamingContent = ""
        errorMessage = nil

        // Create new session in background (actor ensures thread safety)
        Task {
            _ = await SessionManager.shared.startNewSession()
        }
    }

    /// Load the current session from persistence
    private func loadCurrentSession() async {
        let session = await SessionManager.shared.getCurrentSession()
        let savedMessages = session.messages

        // Convert saved messages to ChatMessages for display
        for message in savedMessages {
            if message.role == .user || message.role == .assistant {
                messages.append(ChatMessage(role: message.role, content: message.content))
            }
        }

        // Load into agent
        agent.loadMessages(savedMessages)
    }

    /// Save the current session
    private func saveCurrentSession() async {
        let messagesToSave = agent.getMessagesForSave()
        await SessionManager.shared.updateCurrentSession(messages: messagesToSave)
    }

    /// Switch to a different session
    func switchToSession(id: UUID) async {
        // Cancel any running task first
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        canCancel = false
        streamingContent = ""

        // Save current session before switching
        await saveCurrentSession()

        if let session = await SessionManager.shared.switchToSession(id: id) {
            messages.removeAll()
            agent.reset()

            // Load messages from session
            for message in session.messages {
                if message.role == .user || message.role == .assistant {
                    messages.append(ChatMessage(role: message.role, content: message.content))
                }
            }
            agent.loadMessages(session.messages)
        }
    }

    /// Get all sessions for history display
    func getAllSessions() async -> [Session] {
        await SessionManager.shared.getAllSessions()
    }

    /// Get the current session ID
    func getCurrentSessionId() async -> UUID? {
        await SessionManager.shared.getCurrentSessionId()
    }

    /// Delete a session
    func deleteSession(id: UUID) async {
        await SessionManager.shared.deleteSession(id: id)
    }

    func confirmTool(_ approved: Bool) {
        guard let confirmation = pendingToolConfirmation else { return }
        toolConfirmationContinuations[confirmation.id]?.resume(returning: approved)
        toolConfirmationContinuations.removeValue(forKey: confirmation.id)
        pendingToolConfirmation = nil
    }

    // MARK: - AgentCallbacks

    func onThinking() {
        // Clear streaming content for each new ReAct iteration
        streamingContent = ""
    }

    func onToolCall(name: String, arguments: String) {
        let displayName = formatToolDisplayName(name)
        let toolMessage = ChatMessage(
            role: .tool,
            content: displayName,
            toolName: name,
            toolStatus: .running
        )
        messages.append(toolMessage)
    }

    func onToolConfirmation(name: String, arguments: String) async -> Bool {
        let confirmation = ToolConfirmation(name: name, arguments: arguments)
        pendingToolConfirmation = confirmation

        return await withCheckedContinuation { continuation in
            self.toolConfirmationContinuations[confirmation.id] = continuation
        }
    }

    func onToolResult(name: String, result: String) {
        if let index = messages.lastIndex(where: { $0.toolName == name }) {
            messages[index].toolStatus = .completed
        }
    }

    /// Format tool name for display
    private func formatToolDisplayName(_ name: String) -> String {
        switch name {
        case "weather":
            return "Fetching weather"
        case "location":
            return "Getting location"
        case "calculator":
            return "Calculating"
        case "web_fetch":
            return "Fetching web content"
        case "calendar":
            return "Checking calendar"
        case "contacts":
            return "Searching contacts"
        case "reminders":
            return "Managing reminders"
        case "remember":
            return "Saving to memory"
        default:
            // Convert snake_case to Title Case
            return name.split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    func onStreamChunk(chunk: String) {
        streamingContent += chunk
    }

    func onResponse(content: String) {
        let assistantMessage = ChatMessage(role: .assistant, content: content)
        messages.append(assistantMessage)

        // Speak response in voice mode
        if isVoiceModeActive, let voiceManager = voiceManager {
            // Read voice output setting
            let voiceOutputEnabled = UserDefaults.standard.bool(forKey: "voiceOutputEnabled")
            if voiceOutputEnabled {
                voiceManager.speak(content)
            }
        }
    }

    func onError(error: Error) {
        errorMessage = error.localizedDescription
    }

    // MARK: - Voice Control Methods

    /// Toggle voice input recording
    func toggleVoiceInput() async {
        guard let voiceManager = voiceManager else { return }
        await voiceManager.toggleListening()
    }

    /// Start voice input recording
    func startVoiceInput() async {
        guard let voiceManager = voiceManager else { return }
        await voiceManager.startListening()
    }

    /// Stop voice input and send message
    func stopVoiceInputAndSend() {
        guard let voiceManager = voiceManager else { return }
        voiceManager.stopListening()
    }

    /// Toggle voice mode (hands-free conversation)
    func toggleVoiceMode() async {
        guard let voiceManager = voiceManager else { return }
        await voiceManager.toggleVoiceMode()
    }

    /// Stop any ongoing speech
    func stopSpeaking() {
        voiceManager?.stopSpeaking()
    }

    /// Check if voice features are authorized
    func requestVoiceAuthorization() async -> Bool {
        guard let voiceManager = voiceManager else { return false }
        return await voiceManager.requestAuthorization()
    }
}

/// Status of a tool execution
enum ToolStatus {
    case running
    case completed
    case failed
}

/// A message in the chat UI
struct ChatMessage: Identifiable {
    let id = UUID()
    var role: MessageRole
    var content: String
    var toolName: String?
    var toolStatus: ToolStatus?
    let timestamp = Date()
}

/// Pending tool confirmation
struct ToolConfirmation: Identifiable {
    let id = UUID()
    let name: String
    let arguments: String
}

