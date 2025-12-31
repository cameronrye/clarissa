import Foundation
import SwiftUI
import Combine

/// View model for the chat interface
@MainActor
final class ChatViewModel: ObservableObject, AgentCallbacks {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var streamingContent: String = ""
    @Published var errorMessage: String?
    @Published var currentProvider: String = ""
    @Published var canCancel: Bool = false
    @Published var isSettingUpProvider: Bool = true
    @Published var showNewSessionConfirmation: Bool = false
    @Published var thinkingStatus: ThinkingStatus = .idle
    @Published var isSwitchingSession: Bool = false

    // MARK: - Enhancement Properties
    @Published var isEnhancing: Bool = false

    // MARK: - Voice Properties
    @Published var isRecording: Bool = false
    @Published var isVoiceModeActive: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var voiceTranscript: String = ""

    // MARK: - Context Properties
    @Published var contextStats: ContextStats = .empty

    private var agent: Agent
    private var appState: AppState?
    private var currentTask: Task<Void, Never>?
    private var initTask: Task<Void, Never>?
    private(set) var voiceManager: VoiceManager?
    private var voiceCancellables = Set<AnyCancellable>()
    #if os(macOS)
    private var menuCommandCancellables = Set<AnyCancellable>()
    #endif

    init() {
        self.agent = Agent()
        self.agent.callbacks = self

        // Set up provider (default to Foundation Models if available)
        // Store reference so we can cancel if configure(with:) is called before completion
        initTask = Task {
            await setupProvider()
            await loadCurrentSession()
            isSettingUpProvider = false
        }

        // Initialize voice manager on both platforms
        setupVoiceManager()

        // Set up menu command observers on macOS
        #if os(macOS)
        setupMenuCommandObservers()
        #endif
    }

    // Note: VoiceManager cleanup is handled via scenePhase in ChatView
    // Do NOT use Task in deinit - it's undefined behavior and may not complete
    // VoiceManager's own deinit handles NotificationCenter observer removal

    // MARK: - macOS Menu Command Observers

    #if os(macOS)
    private func setupMenuCommandObservers() {
        // New conversation command
        NotificationCenter.default.publisher(for: .newConversation)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.requestNewSession()
            }
            .store(in: &menuCommandCancellables)

        // Clear conversation command
        NotificationCenter.default.publisher(for: .clearConversation)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.clearConversation()
            }
            .store(in: &menuCommandCancellables)

        // Voice input toggle command
        NotificationCenter.default.publisher(for: .toggleVoiceInput)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.toggleVoiceInput() }
            }
            .store(in: &menuCommandCancellables)

        // Speak last response command
        NotificationCenter.default.publisher(for: .speakLastResponse)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.speakLastResponse()
            }
            .store(in: &menuCommandCancellables)

        // Stop speaking command
        NotificationCenter.default.publisher(for: .stopSpeaking)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.stopSpeaking()
            }
            .store(in: &menuCommandCancellables)
    }

    /// Clear the current conversation without starting a new session
    private func clearConversation() {
        messages.removeAll()
        streamingContent = ""
        contextStats = .empty
        thinkingStatus = .idle
        cancelGeneration()
    }
    #endif

    // MARK: - Voice Setup

    private func setupVoiceManager() {
        let manager = VoiceManager()
        self.voiceManager = manager

        // Handle transcript ready
        manager.onTranscriptReady = { [weak self] transcript in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.inputText = transcript
                self.voiceTranscript = ""

                // Auto-send in voice mode
                if self.isVoiceModeActive {
                    self.sendMessage()
                }
            }
        }

        // Observe voice manager state using Combine
        manager.speechRecognizer.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isListening in
                self?.isRecording = isListening
            }
            .store(in: &voiceCancellables)

        manager.speechRecognizer.$transcript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transcript in
                guard let self else { return }
                self.voiceTranscript = transcript
                // Update input text while recording
                if self.isRecording {
                    self.inputText = transcript
                }
            }
            .store(in: &voiceCancellables)

        manager.speechSynthesizer.$isSpeaking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speaking in
                self?.isSpeaking = speaking
            }
            .store(in: &voiceCancellables)

        manager.$isVoiceModeActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isActive in
                self?.isVoiceModeActive = isActive
            }
            .store(in: &voiceCancellables)
    }

    /// Configure with AppState for provider switching
    func configure(with appState: AppState) {
        self.appState = appState

        // Cancel any in-progress init task to prevent race condition
        initTask?.cancel()
        initTask = nil

        Task {
            isSettingUpProvider = true
            // Set up provider with fallback if persisted selection is unavailable
            await appState.setProviderWithFallback(appState.selectedProvider) { providerType in
                await self.checkProviderAvailability(providerType)
            }
            await setupProvider(for: appState.selectedProvider)
            await loadCurrentSession()
            isSettingUpProvider = false
        }
    }

    /// Switch to a different provider
    func switchProvider(to providerType: LLMProviderType) async {
        isSettingUpProvider = true
        // Use fallback if the requested provider is unavailable
        if let appState = appState {
            await appState.setProviderWithFallback(providerType) { type in
                await self.checkProviderAvailability(type)
            }
            await setupProvider(for: appState.selectedProvider)
        } else {
            await setupProvider(for: providerType)
        }
        isSettingUpProvider = false
    }

    /// Check if a provider type is available
    private func checkProviderAvailability(_ providerType: LLMProviderType) async -> Bool {
        switch providerType {
        case .foundationModels:
            if #available(iOS 26.0, *) {
                let provider = FoundationModelsProvider()
                return await provider.isAvailable
            }
            return false
        case .openRouter:
            let apiKey = KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? ""
            return !apiKey.isEmpty
        }
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
                // Prewarm the actual session with tools for faster first response
                provider.prewarm(with: "Help me")
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

    /// Format model name for display (e.g., "anthropic/claude-sonnet-4" -> "Claude Sonnet 4")
    private func formatModelName(_ model: String) -> String {
        let parts = model.split(separator: "/")
        if parts.count == 2 {
            return String(parts[1]).replacingOccurrences(of: "-", with: " ").capitalized
        }
        return model
    }

    /// Refresh provider with current settings
    func refreshProvider() {
        Task {
            self.agent = Agent()
            self.agent.callbacks = self
            await setupProvider(for: appState?.selectedProvider)
        }
    }
    
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Cancel any existing task before starting a new one
        currentTask?.cancel()
        currentTask = nil

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
        thinkingStatus = .idle
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
        streamingContent = ""
        errorMessage = nil

        // Reset agent AND provider session to prevent context bleeding
        // This is critical for Foundation Models which cache the LanguageModelSession
        Task {
            await agent.resetForNewConversation()
            await MainActor.run {
                updateContextStats()
            }
            _ = await SessionManager.shared.startNewSession()
        }
    }

    /// Load the current session from persistence
    private func loadCurrentSession() async {
        // In screenshot mode, load demo data instead of real session
        if DemoData.isScreenshotMode {
            loadDemoData()
            return
        }

        let session = await SessionManager.shared.getCurrentSession()
        let savedMessages = session.messages

        ClarissaLogger.ui.info(
            "Loading current session '\(session.title, privacy: .public)' with \(savedMessages.count) messages"
        )

        // Convert saved messages to ChatMessages for display
        var loadedCount = 0
        for message in savedMessages {
            if message.role == .user || message.role == .assistant {
                messages.append(ChatMessage(role: message.role, content: message.content))
                loadedCount += 1
            }
        }

        ClarissaLogger.ui.info("Loaded \(loadedCount) UI messages on startup")

        // Load into agent
        agent.loadMessages(savedMessages)
        updateContextStats()
    }

    /// Load demo data for screenshot mode based on current scenario
    private func loadDemoData() {
        let scenario = DemoData.currentScenario
        switch scenario {
        case .welcome:
            // Empty state with suggestions - no messages needed
            messages = []
        case .conversation:
            messages = DemoData.getConversationChatMessages()
        case .context:
            // Load some messages and set demo context stats for context visualizer
            messages = DemoData.getConversationChatMessages()
            contextStats = DemoData.demoContextStats
        case .settings:
            // Settings screen doesn't need messages
            messages = []
        }
    }

    /// Save the current session
    private func saveCurrentSession() async {
        let messagesToSave = agent.getMessagesForSave()
        await SessionManager.shared.updateCurrentSession(messages: messagesToSave)
    }

    /// Export conversation as markdown text
    func exportConversation() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var markdown = "# Clarissa Conversation\n\n"
        markdown += "_Exported on \(dateFormatter.string(from: Date()))_\n\n"
        markdown += "---\n\n"

        for message in messages {
            if message.role != .system {
                markdown += "\(message.toMarkdown())\n\n"
            }
        }

        return markdown
    }

    /// Switch to a different session
    func switchToSession(id: UUID) async {
        // Cancel any running task first
        currentTask?.cancel()
        currentTask = nil
        isLoading = false
        canCancel = false
        streamingContent = ""

        // Show loading state during session switch
        isSwitchingSession = true
        defer { isSwitchingSession = false }

        // Save current session before switching
        await saveCurrentSession()

        guard let session = await SessionManager.shared.switchToSession(id: id) else {
            ClarissaLogger.ui.error("Failed to switch to session: \(id.uuidString, privacy: .public)")
            return
        }

        ClarissaLogger.ui.info("Switching to session: \(session.title, privacy: .public) with \(session.messages.count) messages")

        // Clear UI messages first
        messages.removeAll()

        // Reset provider session to clear cached context from previous conversation
        await agent.resetForNewConversation()

        // Load messages from session into UI
        var loadedCount = 0
        for message in session.messages {
            if message.role == .user || message.role == .assistant {
                messages.append(ChatMessage(role: message.role, content: message.content))
                loadedCount += 1
            }
        }

        ClarissaLogger.ui.info("Loaded \(loadedCount) UI messages from session")

        // Load into agent for context
        agent.loadMessages(session.messages)
        updateContextStats()
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
        // Check if we're deleting the active conversation
        let currentId = await SessionManager.shared.getCurrentSessionId()
        let isDeletingActiveConversation = currentId == id

        await SessionManager.shared.deleteSession(id: id)

        // If we deleted the active conversation, clear chat and show new conversation screen
        if isDeletingActiveConversation {
            await MainActor.run {
                startNewSession()
            }
        }
    }

    /// Rename a session
    func renameSession(id: UUID, newTitle: String) async {
        await SessionManager.shared.renameSession(id: id, newTitle: newTitle)
    }

    // MARK: - AgentCallbacks

    func onThinking() {
        // Clear streaming content for each new ReAct iteration
        streamingContent = ""
        thinkingStatus = .thinking
    }

    func onToolCall(name: String, arguments: String) {
        let displayName = formatToolDisplayName(name)
        thinkingStatus = .usingTool(displayName)

        let toolMessage = ChatMessage(
            role: .tool,
            content: displayName,
            toolName: name,
            toolStatus: .running
        )
        messages.append(toolMessage)
    }

    func onToolResult(name: String, result: String, success: Bool) {
        if let index = messages.lastIndex(where: { $0.toolName == name }) {
            messages[index].toolStatus = success ? .completed : .failed
            messages[index].toolResult = result
        }
        // After tool completes, we're processing the result
        thinkingStatus = .processing
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
        // Only hide thinking indicator once we have visible content to show
        // This prevents a visual gap when first chunks are empty
        if thinkingStatus.isActive && !streamingContent.isEmpty {
            thinkingStatus = .idle
        }
    }

    func onResponse(content: String) {
        thinkingStatus = .idle

        let assistantMessage = ChatMessage(role: .assistant, content: content)
        messages.append(assistantMessage)

        // Update context stats
        updateContextStats()

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
        thinkingStatus = .idle
        errorMessage = error.localizedDescription
    }

    // MARK: - Context Stats

    /// Update context statistics from the agent
    private func updateContextStats() {
        contextStats = agent.getContextStats()
    }

    // MARK: - Prompt Enhancement

    /// Enhance the current input prompt using the LLM
    func enhanceCurrentPrompt() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isEnhancing else { return }

        // Get the current provider, checking availability
        guard let provider = await getAvailableProvider() else {
            errorMessage = "No provider available for enhancement"
            return
        }

        isEnhancing = true
        HapticManager.shared.lightTap()

        do {
            let enhanced = try await PromptEnhancer.shared.enhance(text, using: provider)
            inputText = enhanced
            HapticManager.shared.success()
        } catch {
            ClarissaLogger.agent.error("Prompt enhancement failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Enhancement failed: \(error.localizedDescription)"
            HapticManager.shared.error()
        }

        isEnhancing = false
    }

    /// Get an available LLM provider, checking availability asynchronously
    private func getAvailableProvider() async -> (any LLMProvider)? {
        // Try Foundation Models first, but check availability
        if #available(iOS 26.0, *) {
            let provider = FoundationModelsProvider()
            if await provider.isAvailable {
                return provider
            }
        }

        // Fall back to OpenRouter
        let apiKey = KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? ""
        let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "anthropic/claude-sonnet-4"
        guard !apiKey.isEmpty else { return nil }
        return OpenRouterProvider(apiKey: apiKey, model: model)
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

    /// Speak arbitrary text using text-to-speech
    func speak(text: String) {
        voiceManager?.speak(text)
    }

    /// Speak the last assistant response using text-to-speech
    func speakLastResponse() {
        guard let voiceManager = voiceManager else { return }

        // Find the last assistant message
        guard let lastAssistantMessage = messages.last(where: { $0.role == .assistant }) else {
            return
        }

        voiceManager.speak(lastAssistantMessage.content)
    }

    /// Check if there's an assistant message that can be spoken
    var canSpeakLastResponse: Bool {
        messages.contains(where: { $0.role == .assistant })
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

/// Current thinking/processing status for the typing indicator
enum ThinkingStatus: Equatable {
    case idle
    case thinking
    case usingTool(String)
    case processing

    /// Display text for the status
    var displayText: String {
        switch self {
        case .idle:
            return ""
        case .thinking:
            return "Thinking"
        case .usingTool(let toolName):
            return toolName
        case .processing:
            return "Processing"
        }
    }

    /// Whether the status is active (should show indicator)
    var isActive: Bool {
        self != .idle
    }
}

/// A message in the chat UI
struct ChatMessage: Identifiable {
    let id = UUID()
    var role: MessageRole
    var content: String
    var toolName: String?
    var toolStatus: ToolStatus?
    var toolResult: String?  // JSON result from tool execution
    let timestamp = Date()

    /// Export message as markdown
    func toMarkdown() -> String {
        switch role {
        case .user:
            return "**You:** \(content)"
        case .assistant:
            return "**Clarissa:** \(content)"
        case .system:
            return "_System: \(content)_"
        case .tool:
            let status = toolStatus == .completed ? "completed" : (toolStatus == .failed ? "failed" : "running")
            return "> Tool: \(toolName ?? "unknown") (\(status))"
        }
    }
}
