#if canImport(CarPlay)
import CarPlay
import Combine
import Foundation

/// Manages CarPlay state, voice interaction, and agent communication
@MainActor
public final class CarPlayViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var isProcessing = false
    @Published var currentTranscript = ""
    @Published var lastResponse = ""
    @Published var error: String?

    // MARK: - Private Properties

    private weak var interfaceController: CPInterfaceController?
    let voiceManager: VoiceManager
    private let agent: Agent
    private var templates: CarPlayTemplateManager?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Conversation History (for list template)

    struct ConversationItem: Identifiable {
        let id = UUID()
        let query: String
        let response: String
        let timestamp: Date
    }

    @Published var recentConversations: [ConversationItem] = []

    // MARK: - Initialization

    public init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
        self.voiceManager = VoiceManager()
        self.agent = Agent()
        self.agent.callbacks = self

        setupVoiceCallbacks()
    }

    // MARK: - Setup

    public func setupInitialTemplate() async {
        guard let interfaceController else { return }

        // Create template manager
        let templateManager = CarPlayTemplateManager(
            interfaceController: interfaceController,
            viewModel: self
        )
        self.templates = templateManager

        // Show the idle voice template
        await templateManager.showIdleTemplate()

        // Set up provider
        await setupProvider()
    }

    private func setupProvider() async {
        // FoundationModelsProvider requires iOS 26+ for Apple Intelligence
        if #available(iOS 26.0, *) {
            let provider = FoundationModelsProvider()
            if await provider.isAvailable {
                agent.setProvider(provider)
                return
            }
        }
        error = "AI not available on this device"
    }

    private func setupVoiceCallbacks() {
        voiceManager.onTranscriptReady = { [weak self] transcript in
            guard let self else { return }
            Task { @MainActor in
                await self.processQuery(transcript)
            }
        }

        // Observe voice manager state
        voiceManager.$isListening
            .receive(on: DispatchQueue.main)
            .assign(to: &$isListening)

        voiceManager.$isSpeaking
            .receive(on: DispatchQueue.main)
            .assign(to: &$isSpeaking)

        voiceManager.$currentTranscript
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentTranscript)
    }

    // MARK: - Voice Control

    func startListening() async {
        error = nil
        currentTranscript = ""

        // Configure audio for CarPlay
        do {
            try await AudioSessionManager.shared.configureForVoiceMode()
        } catch {
            self.error = "Audio setup failed"
            return
        }

        await templates?.showListeningTemplate()
        await voiceManager.startListening()
    }

    func stopListening() {
        voiceManager.stopListening()
    }

    func cancelListening() async {
        voiceManager.stopListening()
        await templates?.showIdleTemplate()
    }

    func stopSpeaking() {
        voiceManager.speechSynthesizer.stop()
    }

    /// Expose conversation history for template manager
    var conversationHistory: [ConversationItem] {
        recentConversations
    }

    // MARK: - Query Processing

    private func processQuery(_ query: String) async {
        isProcessing = true
        currentTranscript = query

        await templates?.showProcessingTemplate(query: query)

        do {
            let response = try await agent.run(query)
            lastResponse = response

            // Add to history
            recentConversations.insert(
                ConversationItem(query: query, response: response, timestamp: Date()),
                at: 0
            )
            // Keep only last 10
            if recentConversations.count > 10 {
                recentConversations = Array(recentConversations.prefix(10))
            }

            // Show speaking template and speak response
            await templates?.showSpeakingTemplate(response: response)
            voiceManager.speak(response)

        } catch {
            self.error = error.localizedDescription
            await templates?.showIdleTemplate()
        }

        isProcessing = false
    }

    // MARK: - Navigation

    func showHistory() async {
        await templates?.showHistoryTemplate(conversations: recentConversations)
    }

    // MARK: - Cleanup

    public func cleanup() async {
        await voiceManager.exitVoiceMode()
        agent.reset()
    }
}

// MARK: - AgentCallbacks

extension CarPlayViewModel: AgentCallbacks {
    func onThinking() {
        isProcessing = true
    }

    func onToolCall(name: String, arguments: String) {
        // Could show tool activity indicator
    }

    func onToolResult(name: String, result: String, success: Bool) {
        // Tool completed
    }

    func onStreamChunk(chunk: String) {
        // Streaming not shown in CarPlay for simplicity
    }

    func onResponse(content: String) {
        lastResponse = content
        isProcessing = false
    }

    func onError(error: any Error) {
        self.error = error.localizedDescription
        isProcessing = false
    }
}
#endif

