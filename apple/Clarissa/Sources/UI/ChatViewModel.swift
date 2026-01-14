import Foundation
import SwiftUI
import Combine
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
    /// Incremented when sessions are created, deleted, or modified to trigger history view refreshes
    @Published var sessionVersion: Int = 0

    // MARK: - Enhancement Properties
    @Published var isEnhancing: Bool = false
    @Published var enhancementFailed: Bool = false

    // MARK: - Voice Properties
    @Published var isRecording: Bool = false
    @Published var isVoiceModeActive: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var voiceTranscript: String = ""

    // MARK: - Context Properties
    @Published var contextStats: ContextStats = .empty

    // MARK: - Image Attachment Properties
    @Published var attachedImageData: Data?
    @Published var attachedImagePreview: Data?  // Thumbnail for display

    // MARK: - Camera Properties
    #if os(iOS)
    @Published var showCameraCapture: Bool = false
    #endif

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

            // Check for cancellation before loading session (in case configure was called)
            guard !Task.isCancelled else { return }

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

        // Cancel any in-progress init task and wait for it to complete
        // This prevents race conditions where multiple initialization tasks run concurrently
        let previousTask = initTask
        initTask = nil

        initTask = Task {
            // Wait for previous task to complete (it will exit early due to cancellation checks)
            previousTask?.cancel()
            _ = await previousTask?.value

            isSettingUpProvider = true
            // Set up provider with fallback if persisted selection is unavailable
            await appState.setProviderWithFallback(appState.selectedProvider) { providerType in
                await self.checkProviderAvailability(providerType)
            }

            // Check for cancellation before continuing
            guard !Task.isCancelled else { return }

            await setupProvider(for: appState.selectedProvider)
            await loadCurrentSession()
            isSettingUpProvider = false
        }
    }

    /// Switch to a different provider
    func switchProvider(to providerType: LLMProviderType) async {
        isSettingUpProvider = true

        // Reset agent to clear any cached context from the previous provider
        // This prevents context bleeding between providers (e.g., Foundation Models session cache)
        await agent.resetForNewConversation()

        // Use fallback if the requested provider is unavailable
        if let appState = appState {
            await appState.setProviderWithFallback(providerType) { type in
                await self.checkProviderAvailability(type)
            }
            await setupProvider(for: appState.selectedProvider)
        } else {
            await setupProvider(for: providerType)
        }

        // Reload the current session into the new provider
        await loadCurrentSession()
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
        let hasImage = attachedImageData != nil

        // Allow sending if there's text OR an image
        guard !text.isEmpty || hasImage else { return }

        // Cancel any existing task before starting a new one
        currentTask?.cancel()
        currentTask = nil

        // Capture and clear input state
        let imageData = attachedImageData
        let imagePreview = attachedImagePreview
        inputText = ""
        attachedImageData = nil
        attachedImagePreview = nil

        // Build message content for display
        var displayContent = text
        if hasImage && text.isEmpty {
            displayContent = "Analyze this image"
        } else if hasImage {
            displayContent = text + " [with image]"
        }

        // Add user message with optional image preview
        var userMessage = ChatMessage(role: .user, content: displayContent)
        userMessage.imageData = imagePreview
        messages.append(userMessage)

        isLoading = true
        canCancel = true
        streamingContent = ""

        currentTask = Task {
            do {
                try Task.checkCancellation()

                // Build prompt for the agent
                var promptText = text.isEmpty ? "Analyze this image" : text

                // Pre-process image BEFORE involving the LLM
                // This is critical for Apple Foundation Models (4,096 token limit)
                // Instead of passing base64 (~100KB = 25,000+ tokens), we pass
                // extracted text/metadata (~500 chars = ~150 tokens)
                if let imageData = imageData {
                    let processor = ImagePreProcessor()
                    let result = await processor.process(imageData: imageData)

                    // Add extracted content to the prompt
                    promptText = """
                    \(promptText)

                    \(result.contextString)
                    """
                }

                // Pass image preview for persistence (not the full image)
                _ = try await agent.run(promptText, imageData: imagePreview)
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

    /// Attach an image for analysis
    func attachImage(_ data: Data) {
        attachedImageData = data
        // Create a smaller preview for display
        attachedImagePreview = createImagePreview(from: data)
        HapticManager.shared.lightTap()
    }

    /// Remove the attached image
    func removeAttachedImage() {
        attachedImageData = nil
        attachedImagePreview = nil
        HapticManager.shared.lightTap()
    }

    // MARK: - Camera Methods

    #if os(iOS)
    /// Show the camera capture interface
    func showCamera() {
        showCameraCapture = true
    }

    /// Handle captured image from camera
    func handleCameraCapture(_ capturedImage: CapturedImage) {
        attachImage(capturedImage.imageData)
        showCameraCapture = false
    }

    /// Dismiss camera without capturing
    func dismissCamera() {
        showCameraCapture = false
    }
    #endif

    /// Create a thumbnail preview from image data
    private func createImagePreview(from data: Data) -> Data? {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return nil }
        let maxSize: CGFloat = 200
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resized?.jpegData(compressionQuality: 0.7)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else { return nil }
        let maxSize: CGFloat = 200
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        resized.unlockFocus()

        guard let tiffData = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        #endif
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
            Task {
                await startNewSession()
            }
        }
    }

    /// Actually start a new session (called after confirmation or if no messages)
    func startNewSession() async {
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
        await agent.resetForNewConversation()
        _ = await SessionManager.shared.startNewSession()
        updateContextStats()

        // Notify history views to refresh
        sessionVersion += 1
    }

    /// Load the current session from persistence
    private func loadCurrentSession() async {
        // In screenshot mode, load demo data instead of real session
        // Only available in DEBUG builds for App Store screenshots
        #if DEBUG
        if DemoData.isScreenshotMode {
            loadDemoData()
            return
        }
        #endif

        let session = await SessionManager.shared.getCurrentSession()
        let savedMessages = session.messages

        ClarissaLogger.ui.info(
            "Loading current session '\(session.title, privacy: .public)' with \(savedMessages.count) messages"
        )

        // Convert saved messages to ChatMessages for display
        var loadedCount = 0
        for message in savedMessages {
            if message.role == .user || message.role == .assistant {
                var chatMessage = ChatMessage(role: message.role, content: message.content)
                chatMessage.imageData = message.imageData
                messages.append(chatMessage)
                loadedCount += 1
            }
        }

        ClarissaLogger.ui.info("Loaded \(loadedCount) UI messages on startup")

        // Load into agent
        agent.loadMessages(savedMessages)
        updateContextStats()

        // Refresh widgets with current session data
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Load demo data for screenshot mode based on current scenario
    /// Only available in DEBUG builds for App Store screenshots
    #if DEBUG
    private func loadDemoData() {
        let scenario = DemoData.currentScenario
        messages = DemoData.getMessagesForScenario(scenario)

        // Set demo context stats for context visualizer scenario
        if scenario == .context {
            contextStats = DemoData.demoContextStats
        }
    }
    #endif

    /// Save the current session
    private func saveCurrentSession() async {
        let messagesToSave = agent.getMessagesForSave()
        await SessionManager.shared.updateCurrentSession(messages: messagesToSave)
        // Notify history views to refresh (session may have new title or content)
        sessionVersion += 1
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
                var chatMessage = ChatMessage(role: message.role, content: message.content)
                chatMessage.imageData = message.imageData
                messages.append(chatMessage)
                loadedCount += 1
            }
        }

        ClarissaLogger.ui.info("Loaded \(loadedCount) UI messages from session")

        // Load into agent for context
        agent.loadMessages(session.messages)
        updateContextStats()

        // Refresh widgets after session switch
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
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
            // Cancel any running task first
            currentTask?.cancel()
            currentTask = nil
            isLoading = false
            canCancel = false

            // Clear UI state immediately
            messages.removeAll()
            streamingContent = ""
            errorMessage = nil

            // Reset agent AND provider session, then create new session synchronously
            await agent.resetForNewConversation()
            _ = await SessionManager.shared.startNewSession()
            updateContextStats()
        }

        // Notify history views to refresh
        sessionVersion += 1
    }

    /// Rename a session
    func renameSession(id: UUID, newTitle: String) async {
        await SessionManager.shared.renameSession(id: id, newTitle: newTitle)
        // Notify history views to refresh
        sessionVersion += 1
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

        // Update widget data with last conversation
        if let lastUserMessage = messages.last(where: { $0.role == .user }) {
            WidgetDataManager.shared.updateLastConversation(
                message: lastUserMessage.content,
                response: content
            )
        }

        // Speak response in voice mode
        if isVoiceModeActive, let voiceManager = voiceManager {
            // Read voice output setting - default to true to match @AppStorage default in SettingsView
            // Note: UserDefaults.bool(forKey:) returns false if key doesn't exist,
            // so we need to check if the key exists first
            let voiceOutputEnabled: Bool
            if UserDefaults.standard.object(forKey: "voiceOutputEnabled") == nil {
                // Key not set yet, use default of true
                voiceOutputEnabled = true
            } else {
                voiceOutputEnabled = UserDefaults.standard.bool(forKey: "voiceOutputEnabled")
            }

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
            // Show subtle failure indicator instead of intrusive alert
            enhancementFailed = true
            HapticManager.shared.error()
            // Auto-dismiss after a brief moment
            Task {
                try? await Task.sleep(for: .seconds(2))
                enhancementFailed = false
            }
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
    var imageData: Data?  // Optional attached image preview
    let timestamp = Date()

    /// Export message as markdown
    func toMarkdown() -> String {
        switch role {
        case .user:
            // Only add image note if not already in content and we have image data
            let hasImageNote = content.contains("[with image]")
            let imageNote = (imageData != nil && !hasImageNote) ? " [with image]" : ""
            return "**You:** \(content)\(imageNote)"
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
