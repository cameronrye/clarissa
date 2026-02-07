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
    @Published var planSteps: [PlanStep] = []
    @Published var isSwitchingSession: Bool = false
    /// Incremented when sessions are created, deleted, or modified to trigger history view refreshes
    @Published var sessionVersion: Int = 0
    @Published var showPCCConsent: Bool = false
    @Published var pendingSharedResult: SharedResult?
    @Published var conversationSummarizedBanner: Bool = false
    /// Suggests switching to OpenRouter after an FM failure
    @Published var showProviderSuggestion: Bool = false

    // MARK: - Undo State (ephemeral, does not survive app restart)
    /// Stores replaced messages for one-level undo after edit/regenerate
    private(set) var undoSnapshot: [ChatMessage]?

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

    // MARK: - Coordinators & Internal State

    private var agent: Agent
    private var appState: AppState?
    private var currentTask: Task<Void, Never>?
    private var initTask: Task<Void, Never>?
    let providerCoordinator: ProviderCoordinator
    let sessionCoordinator: SessionCoordinator
    let voiceController: VoiceController
    private var toolCallCount = 0
    private var pendingProactiveLabels: [String]?
    #if os(macOS)
    private var menuCommandCancellables = Set<AnyCancellable>()
    #endif
    #if os(iOS)
    private var sharedResultCancellable: AnyCancellable?
    #endif

    init() {
        self.agent = Agent()
        self.providerCoordinator = ProviderCoordinator(agent: agent)
        self.sessionCoordinator = SessionCoordinator(agent: agent)
        self.voiceController = VoiceController()
        self.agent.callbacks = self

        // Set up provider (default to Foundation Models if available)
        initTask = Task {
            currentProvider = await providerCoordinator.setupProvider(appState: nil)

            guard !Task.isCancelled else { return }

            await loadSession()
            isSettingUpProvider = false
        }

        // Initialize voice manager on both platforms
        setupVoiceCallbacks()

        // Set up menu command observers on macOS
        #if os(macOS)
        setupMenuCommandObservers()
        #endif

        // Listen for shared content from Share Extension
        #if os(iOS)
        sharedResultCancellable = NotificationCenter.default.publisher(for: .checkSharedResults)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.checkForSharedResults()
            }
        #endif
    }

    // Note: VoiceManager cleanup is handled via scenePhase in ChatView
    // Do NOT use Task in deinit - it's undefined behavior and may not complete
    // VoiceManager's own deinit handles NotificationCenter observer removal

    // MARK: - Voice Setup

    private func setupVoiceCallbacks() {
        voiceController.onRecordingChanged = { [weak self] isRecording in
            self?.isRecording = isRecording
        }

        voiceController.onTranscriptChanged = { [weak self] transcript in
            guard let self else { return }
            self.voiceTranscript = transcript
            // Update input text while recording
            if self.isRecording {
                self.inputText = transcript
            }
        }

        voiceController.onSpeakingChanged = { [weak self] speaking in
            self?.isSpeaking = speaking
        }

        voiceController.onVoiceModeChanged = { [weak self] isActive in
            self?.isVoiceModeActive = isActive
        }

        voiceController.onTranscriptReady = { [weak self] transcript in
            guard let self else { return }
            self.inputText = transcript
            self.voiceTranscript = ""

            // Auto-send in voice mode
            if self.isVoiceModeActive {
                self.sendMessage()
            }
        }

        voiceController.setup()
    }

    // MARK: - macOS Menu Command Observers

    #if os(macOS)
    private func setupMenuCommandObservers() {
        NotificationCenter.default.publisher(for: .newConversation)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.requestNewSession() }
            .store(in: &menuCommandCancellables)

        NotificationCenter.default.publisher(for: .clearConversation)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.clearConversation() }
            .store(in: &menuCommandCancellables)

        NotificationCenter.default.publisher(for: .toggleVoiceInput)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.toggleVoiceInput() }
            }
            .store(in: &menuCommandCancellables)

        NotificationCenter.default.publisher(for: .speakLastResponse)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.speakLastResponse() }
            .store(in: &menuCommandCancellables)

        NotificationCenter.default.publisher(for: .stopSpeaking)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.stopSpeaking() }
            .store(in: &menuCommandCancellables)
    }

    /// Clear the current conversation and reset agent state
    private func clearConversation() {
        cancelGeneration()
        messages.removeAll()
        streamingContent = ""
        errorMessage = nil
        contextStats = .empty
        thinkingStatus = .idle

        // Reset agent AND provider session to prevent context bleeding
        Task {
            await sessionCoordinator.startNewSession()
            updateContextStats()
            sessionVersion += 1
        }
    }
    #endif

    // MARK: - Provider Configuration

    /// Configure with AppState for provider switching
    func configure(with appState: AppState) {
        self.appState = appState

        // Cancel any in-progress init task and wait for it to complete
        let previousTask = initTask
        initTask = nil

        initTask = Task {
            // Wait for previous task to complete (it will exit early due to cancellation checks)
            previousTask?.cancel()
            _ = await previousTask?.value

            isSettingUpProvider = true
            // Set up provider with fallback if persisted selection is unavailable
            await appState.setProviderWithFallback(appState.selectedProvider) { providerType in
                await self.providerCoordinator.checkAvailability(providerType)
            }

            // Check for cancellation before continuing
            guard !Task.isCancelled else { return }

            currentProvider = await providerCoordinator.setupProvider(
                for: appState.selectedProvider, appState: appState
            )
            await loadSession()
            isSettingUpProvider = false
        }
    }

    /// Switch to a different provider
    func switchProvider(to providerType: LLMProviderType) async {
        isSettingUpProvider = true
        currentProvider = await providerCoordinator.switchProvider(to: providerType, appState: appState)
        // Reload the current session into the new provider
        await loadSession()
        isSettingUpProvider = false
    }

    /// Refresh provider with current settings
    func refreshProvider() {
        Task {
            await agent.resetForNewConversation()
            currentProvider = await providerCoordinator.setupProvider(
                for: appState?.selectedProvider, appState: appState
            )
        }
    }

    /// Grant PCC consent and recreate the provider
    func grantPCCConsent() {
        providerCoordinator.grantPCCConsent()
        showPCCConsent = false
        refreshProvider()
    }

    // MARK: - Conversation Templates

    /// Start a new conversation with a template
    func startWithTemplate(_ template: ConversationTemplate) {
        Task {
            // Start a fresh session
            await startNewSession()

            // Apply the template to the agent
            agent.applyTemplate(template)

            // If the template has an initial prompt, send it
            if let initialPrompt = template.initialPrompt {
                inputText = initialPrompt
                sendMessage()
            }
        }
    }

    /// Clear any active template (returns to default behavior)
    func clearTemplate() {
        agent.applyTemplate(nil)
    }

    // MARK: - Messaging

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
            // Build prompt for the agent (declared before do/catch so catch can reference it for retry)
            var promptText = text.isEmpty ? "Analyze this image" : text

            do {
                try Task.checkCancellation()

                // Pre-process image BEFORE involving the LLM
                if let imageData = imageData {
                    let processor = ImagePreProcessor()
                    let result = await processor.process(imageData: imageData)

                    promptText = """
                    \(promptText)

                    \(result.contextString)
                    """
                }

                // Pass image preview for persistence (not the full image)
                _ = try await agent.run(promptText, imageData: imagePreview)
                // Save session after successful response
                await sessionCoordinator.saveCurrentSession()
                sessionVersion += 1
            } catch is CancellationError {
                // User cancelled - don't show error
                streamingContent = ""
            } catch {
                // Auto-recovery: if contextWindowExceeded, aggressively trim and retry once
                let isContextOverflow: Bool
                if let fmError = error as? FoundationModelsError,
                   case .contextWindowExceeded = fmError {
                    isContextOverflow = true
                } else {
                    isContextOverflow = false
                }

                if isContextOverflow {
                    // Log token estimate at overflow for future calibration
                    let stats = self.agent.getContextStats()
                    ClarissaLogger.agent.warning("contextWindowExceeded: estimated \(stats.currentTokens) tokens (\(stats.messageCount) messages, \(stats.trimmedCount) already trimmed)")

                    let didTrim = await self.agent.aggressiveTrim()
                    if didTrim {
                        self.conversationSummarizedBanner = true
                        // Retry with compressed context
                        do {
                            _ = try await self.agent.run(promptText, imageData: imagePreview)
                            await self.sessionCoordinator.saveCurrentSession()
                            self.sessionVersion += 1
                        } catch {
                            // Recovery failed — show original error
                            self.errorMessage = ErrorMapper.userFriendlyMessage(for: error)
                        }
                        // Auto-dismiss banner after a few seconds
                        Task {
                            try? await Task.sleep(for: .seconds(5))
                            self.conversationSummarizedBanner = false
                        }
                    } else {
                        self.errorMessage = ErrorMapper.userFriendlyMessage(for: error)
                    }
                } else {
                    self.errorMessage = ErrorMapper.userFriendlyMessage(for: error)
                    // Suggest OpenRouter if FM failed and OpenRouter is configured
                    self.suggestProviderIfAppropriate(error: error)
                }
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

        // End any active Live Activity and reset tool call tracking
        #if os(iOS)
        if #available(iOS 16.1, *) {
            if toolCallCount >= 2 {
                LiveActivityManager.shared.endActivity()
            }
        }
        #endif
        toolCallCount = 0
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

    // MARK: - Edit & Regenerate

    /// Edit a user message and resend from that point
    /// Truncates conversation from the edit point, populates the input field for editing
    func editAndResend(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId && $0.role == .user }) else { return }

        // Save undo snapshot (one level)
        undoSnapshot = messages

        let originalContent = messages[index].content
        // Remove [with image] suffix from display content if present
        let editableContent = originalContent.replacingOccurrences(of: " [with image]", with: "")

        // Truncate conversation from edit point onward
        messages.removeSubrange(index...)

        // Populate input field for editing
        inputText = editableContent

        // Sync trimmed agent state
        syncAgentMessages()

        HapticManager.shared.lightTap()
    }

    /// Regenerate the assistant response for a given message
    /// Removes the assistant message and everything after it, then re-runs the agent
    func regenerateResponse(messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId && $0.role == .assistant }) else { return }

        // Save undo snapshot (one level)
        undoSnapshot = messages

        // Find the user message that preceded this assistant response
        let precedingUserMessage = messages[..<index].last(where: { $0.role == .user })

        // Remove assistant message and everything after it
        messages.removeSubrange(index...)

        // Sync agent state
        syncAgentMessages()

        // Re-run with the same user input
        guard let userMessage = precedingUserMessage else { return }
        inputText = userMessage.content.replacingOccurrences(of: " [with image]", with: "")

        // Remove the user message too (sendMessage will re-add it)
        if let userIndex = messages.lastIndex(where: { $0.role == .user }) {
            messages.removeSubrange(userIndex...)
            syncAgentMessages()
        }

        sendMessage()
    }

    /// Undo the last edit/regenerate operation (one level)
    func undoEditOrRegenerate() {
        guard let snapshot = undoSnapshot else { return }
        messages = snapshot
        undoSnapshot = nil
        syncAgentMessages()
        HapticManager.shared.lightTap()
    }

    /// Whether an undo is available
    var canUndo: Bool { undoSnapshot != nil }

    /// Sync agent's internal message history with current UI messages
    private func syncAgentMessages() {
        // Convert ChatMessages back to agent Messages for context
        let agentMessages: [Message] = messages.compactMap { chat in
            switch chat.role {
            case .user:
                return .user(chat.content, imageData: chat.imageData)
            case .assistant:
                return .assistant(chat.content)
            case .tool:
                return .tool(callId: UUID().uuidString, name: chat.toolName ?? "tool", content: chat.toolResult ?? chat.content)
            case .system:
                return nil  // System message rebuilt on each run()
            }
        }
        agent.loadMessages(agentMessages)
    }

    // MARK: - Image Attachment

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
    func showCamera() { showCameraCapture = true }

    func handleCameraCapture(_ capturedImage: CapturedImage) {
        attachImage(capturedImage.imageData)
        showCameraCapture = false
    }

    func dismissCamera() { showCameraCapture = false }
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

    // MARK: - Session Management

    /// Request to start a new session (may show confirmation if messages exist)
    func requestNewSession() {
        if !messages.isEmpty {
            showNewSessionConfirmation = true
        } else {
            Task { await startNewSession() }
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
        undoSnapshot = nil

        // Clear any active template
        clearTemplate()

        await sessionCoordinator.startNewSession()
        updateContextStats()

        // Notify history views to refresh
        sessionVersion += 1
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
        await sessionCoordinator.saveCurrentSession()
        sessionVersion += 1

        guard let chatMessages = await sessionCoordinator.switchToSession(id: id) else { return }

        // Clear UI messages first, then load new ones
        messages = chatMessages
        updateContextStats()
    }

    /// Delete a session
    func deleteSession(id: UUID) async {
        let isDeletingActive = await sessionCoordinator.deleteSession(id: id)

        // If we deleted the active conversation, clear chat
        if isDeletingActive {
            currentTask?.cancel()
            currentTask = nil
            isLoading = false
            canCancel = false

            messages.removeAll()
            streamingContent = ""
            errorMessage = nil
            updateContextStats()
        }

        sessionVersion += 1
    }

    /// Rename a session
    func renameSession(id: UUID, newTitle: String) async {
        await sessionCoordinator.renameSession(id: id, newTitle: newTitle)
        sessionVersion += 1
    }

    /// Get all sessions for history display
    func getAllSessions() async -> [Session] {
        await sessionCoordinator.getAllSessions()
    }

    /// Get the current session ID
    func getCurrentSessionId() async -> UUID? {
        await sessionCoordinator.getCurrentSessionId()
    }

    /// Export conversation as markdown text
    func exportConversation() -> String {
        sessionCoordinator.exportConversation(from: messages)
    }

    /// Export conversation as PDF data
    func exportConversationAsPDF() async -> Data? {
        #if canImport(WebKit)
        await sessionCoordinator.exportConversationAsPDF(from: messages)
        #else
        nil
        #endif
    }

    // MARK: - Share Extension

    /// Check for shared content from the Share Extension
    func checkForSharedResults() {
        if let result = sessionCoordinator.checkForSharedResults() {
            pendingSharedResult = result
        }
    }

    /// Insert shared content into the conversation
    func insertSharedResult(_ result: SharedResult) {
        messages.append(sessionCoordinator.buildSharedResultMessage(result))
        pendingSharedResult = nil
    }

    /// Dismiss the shared result banner
    func dismissSharedResult() {
        pendingSharedResult = nil
    }

    // MARK: - Voice Control Methods

    func toggleVoiceInput() async { await voiceController.toggleVoiceInput() }
    func startVoiceInput() async { await voiceController.startVoiceInput() }
    func stopVoiceInputAndSend() { voiceController.stopVoiceInputAndSend() }
    func toggleVoiceMode() async { await voiceController.toggleVoiceMode() }
    func stopSpeaking() { voiceController.stopSpeaking() }
    func speak(text: String) { voiceController.speak(text) }

    /// Speak the last assistant response using text-to-speech
    func speakLastResponse() {
        guard let lastAssistant = messages.last(where: { $0.role == .assistant }) else { return }
        voiceController.speak(lastAssistant.content)
    }

    /// Check if there's an assistant message that can be spoken
    var canSpeakLastResponse: Bool {
        messages.contains(where: { $0.role == .assistant })
    }

    /// Check if voice features are authorized
    func requestVoiceAuthorization() async -> Bool {
        await voiceController.requestAuthorization()
    }

    // MARK: - Prompt Enhancement

    /// Enhance the current input prompt using the LLM
    func enhanceCurrentPrompt() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isEnhancing else { return }

        guard let provider = await providerCoordinator.getAvailableProvider() else {
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

    // MARK: - Context Stats

    /// Manually summarize the conversation to free up context space
    func manualSummarize() {
        Task {
            let didTrim = await agent.aggressiveTrim()
            if didTrim {
                conversationSummarizedBanner = true
                updateContextStats()
                HapticManager.shared.success()
                // Auto-dismiss banner after 5 seconds
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    conversationSummarizedBanner = false
                }
            }
        }
    }

    /// Suggest switching to OpenRouter when the current provider (FM) fails
    /// Only shown when: using FM, OpenRouter is configured, error is not context overflow
    private func suggestProviderIfAppropriate(error: Error) {
        guard appState?.selectedProvider == .foundationModels else { return }
        // Don't suggest if OpenRouter isn't configured
        let hasApiKey = !(KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? "").isEmpty
        guard hasApiKey else { return }

        showProviderSuggestion = true
        // Auto-dismiss after 8 seconds
        Task {
            try? await Task.sleep(for: .seconds(8))
            showProviderSuggestion = false
        }
    }

    /// Switch to OpenRouter when user taps the provider suggestion banner
    func switchToOpenRouter() {
        showProviderSuggestion = false
        Task {
            let name = await providerCoordinator.switchProvider(to: .openRouter, appState: appState)
            currentProvider = name
        }
    }

    /// Update context statistics from the agent
    private func updateContextStats() {
        contextStats = agent.getContextStats()
    }

    // MARK: - Private Helpers

    /// Load the current session (handles demo mode for screenshots)
    private func loadSession() async {
        // In screenshot mode, load demo data instead of real session
        #if DEBUG
        if DemoData.isScreenshotMode {
            messages = DemoData.getMessagesForScenario(DemoData.currentScenario)
            if DemoData.currentScenario == .context {
                contextStats = DemoData.demoContextStats
            }
            return
        }
        #endif

        messages = await sessionCoordinator.loadCurrentSession()
        updateContextStats()
    }

    // MARK: - AgentCallbacks

    func onThinking() {
        // Clear streaming content for each new ReAct iteration
        streamingContent = ""
        thinkingStatus = .thinking
    }

    func onToolCall(name: String, arguments: String) {
        let displayName = ToolDisplayNames.format(name)
        thinkingStatus = .usingTool(displayName)

        // Update plan steps: mark previous running step as completed
        if let runningIndex = planSteps.firstIndex(where: { $0.status == .running }) {
            planSteps[runningIndex].status = .completed
        }
        planSteps.append(PlanStep(toolName: name, displayName: displayName, status: .running))

        let toolMessage = ChatMessage(
            role: .tool,
            content: displayName,
            toolName: name,
            toolStatus: .running
        )
        messages.append(toolMessage)

        // Live Activity: start on 2nd tool call (multi-tool detection)
        #if os(iOS)
        toolCallCount += 1
        if #available(iOS 16.1, *) {
            let stepNames = planSteps.map(\.displayName)
            if toolCallCount == 2 {
                let question = messages.last(where: { $0.role == .user })?.content ?? "Working..."
                LiveActivityManager.shared.startActivity(question: question, currentTool: displayName)
            } else if toolCallCount > 2 {
                LiveActivityManager.shared.updateTool(name: displayName, planStepNames: stepNames)
            }
        }
        #endif
    }

    func onToolResult(name: String, result: String, success: Bool) {
        // Match on both tool name AND running status to avoid overwriting
        // the wrong message when the same tool is called multiple times
        if let index = messages.lastIndex(where: { $0.toolName == name && $0.toolStatus == .running }) {
            messages[index].toolStatus = success ? .completed : .failed
            messages[index].toolResult = result
        } else if let index = messages.lastIndex(where: { $0.toolName == name }) {
            // Fallback: match by name only (for native tool handling where status may vary)
            messages[index].toolStatus = success ? .completed : .failed
            messages[index].toolResult = result
        }

        // Update plan step status
        if let stepIndex = planSteps.lastIndex(where: { $0.toolName == name && $0.status == .running }) {
            planSteps[stepIndex].status = success ? .completed : .failed
        }

        // After tool completes, we're processing the result
        thinkingStatus = .processing

        // Live Activity: mark step complete
        #if os(iOS)
        if #available(iOS 16.1, *) {
            LiveActivityManager.shared.completeStep()
        }
        #endif
    }

    func onStreamChunk(chunk: String) {
        streamingContent += chunk
        // Only hide thinking indicator once we have visible content to show
        if thinkingStatus.isActive && !streamingContent.isEmpty {
            thinkingStatus = .idle
        }
    }

    func onProactiveContext(labels: [String]) {
        pendingProactiveLabels = labels
    }

    func onResponse(content: String) {
        thinkingStatus = .idle
        planSteps = []

        // End Live Activity
        #if os(iOS)
        if #available(iOS 16.1, *) {
            if toolCallCount >= 2 {
                LiveActivityManager.shared.endActivity()
            }
        }
        toolCallCount = 0
        #endif

        var assistantMessage = ChatMessage(role: .assistant, content: content)
        // Attach proactive context labels if any were used for this response
        if let labels = pendingProactiveLabels {
            assistantMessage.proactiveLabels = labels
            pendingProactiveLabels = nil
        }
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
        if isVoiceModeActive, let voiceManager = voiceController.voiceManager {
            // Read voice output setting - default to true to match @AppStorage default in SettingsView
            let voiceOutputEnabled: Bool
            if UserDefaults.standard.object(forKey: "voiceOutputEnabled") == nil {
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
        planSteps = []

        // End Live Activity on error
        #if os(iOS)
        if #available(iOS 16.1, *) {
            if toolCallCount >= 2 {
                LiveActivityManager.shared.endActivity()
            }
        }
        toolCallCount = 0
        #endif

        // Check if this is a context window exceeded error and PCC isn't enabled
        if let fmError = error as? FoundationModelsError,
           case .contextWindowExceeded = fmError,
           !UserDefaults.standard.bool(forKey: "pccConsentGiven") {
            showPCCConsent = true
            return
        }

        errorMessage = error.localizedDescription
    }
}
