#if os(iOS)
import ClarissaKit
import Foundation

/// Handles queries from Apple Watch and relays them to the Agent
/// This runs on the iPhone and processes Watch requests
@MainActor
final class WatchQueryHandler: ObservableObject {
    static let shared = WatchQueryHandler()

    private var agent: Agent?
    private var currentCallbacks: WatchAgentCallbacks?
    private let connectivity = WatchConnectivityManager.shared

    private init() {
        setupConnectivity()
    }
    
    /// Initialize the handler and start listening for Watch queries
    func start() {
        connectivity.activate()
        ClarissaLogger.agent.info("WatchQueryHandler started")
    }
    
    private func setupConnectivity() {
        connectivity.onQueryReceived = { [weak self] request in
            await self?.handleQuery(request) ?? QueryResponse(
                requestId: request.id,
                text: "iPhone app not ready"
            )
        }
    }
    
    /// Handle an incoming query from the Watch
    private func handleQuery(_ request: QueryRequest) async -> QueryResponse {
        ClarissaLogger.agent.info("Processing Watch query: \(request.text.prefix(50), privacy: .public)...")
        
        // Send status update
        connectivity.sendStatus(ProcessingStatus(requestId: request.id, status: .thinking))
        
        do {
            // Create a fresh agent for this query
            let agent = Agent()
            self.agent = agent
            
            // Set up the provider based on current settings
            let provider = await createProvider()
            agent.setProvider(provider)
            
            // Set up callbacks to relay status to Watch
            // Store in property to keep alive during query execution
            let callbacks = WatchAgentCallbacks(
                requestId: request.id,
                connectivity: connectivity
            )
            self.currentCallbacks = callbacks
            agent.callbacks = callbacks
            
            // Run the query
            let response = try await agent.run(request.text)
            
            ClarissaLogger.agent.info("Watch query completed successfully")
            return QueryResponse(requestId: request.id, text: response)
            
        } catch {
            ClarissaLogger.agent.error("Watch query failed: \(error.localizedDescription, privacy: .public)")
            connectivity.sendError(ErrorInfo(
                requestId: request.id,
                message: error.localizedDescription,
                isRecoverable: true
            ))
            return QueryResponse(requestId: request.id, text: "Error: \(error.localizedDescription)")
        }
    }
    
    /// Create the appropriate LLM provider based on current settings
    private func createProvider() async -> any LLMProvider {
        let providerType = AppState.shared.selectedProvider

        switch providerType {
        case .foundationModels:
            return FoundationModelsProvider()
        case .openRouter:
            let apiKey = KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? ""
            let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "anthropic/claude-sonnet-4"
            return OpenRouterProvider(apiKey: apiKey, model: model)
        }
    }
}

// MARK: - Watch Agent Callbacks

/// Callbacks that relay agent events to the Watch
@MainActor
private final class WatchAgentCallbacks: AgentCallbacks {
    let requestId: UUID
    let connectivity: WatchConnectivityManager
    
    init(requestId: UUID, connectivity: WatchConnectivityManager) {
        self.requestId = requestId
        self.connectivity = connectivity
    }
    
    func onThinking() {
        connectivity.sendStatus(ProcessingStatus(requestId: requestId, status: .thinking))
    }
    
    func onToolCall(name: String, arguments: String) {
        connectivity.sendStatus(ProcessingStatus(requestId: requestId, status: .usingTool))
    }
    
    func onToolResult(name: String, result: String, success: Bool) {
        connectivity.sendStatus(ProcessingStatus(requestId: requestId, status: .processing))
    }
    
    func onStreamChunk(chunk: String) {
        // We don't stream to Watch - just wait for final response
    }
    
    func onResponse(content: String) {
        connectivity.sendStatus(ProcessingStatus(requestId: requestId, status: .completed))
    }
    
    func onError(error: Error) {
        connectivity.sendError(ErrorInfo(
            requestId: requestId,
            message: error.localizedDescription,
            isRecoverable: true
        ))
    }
}
#endif
