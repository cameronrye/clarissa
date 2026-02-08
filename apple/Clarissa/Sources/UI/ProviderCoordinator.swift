import Foundation

/// Coordinates LLM provider initialization, switching, and availability checks
@MainActor
final class ProviderCoordinator {
    private let agent: Agent

    init(agent: Agent) {
        self.agent = agent
    }

    /// Set up the appropriate provider on the agent
    /// - Returns: The provider display name
    func setupProvider(for providerType: LLMProviderType? = nil, appState: AppState?) async -> String {
        let selectedType = providerType ?? appState?.selectedProvider

        // If OpenRouter is explicitly selected, use it
        if selectedType == .openRouter {
            return setupOpenRouterProvider()
        }

        // Default: try Foundation Models first
        if #available(iOS 26.0, macOS 26.0, *) {
            let pccAllowed = UserDefaults.standard.bool(forKey: "pccConsentGiven")
            let provider = FoundationModelsProvider(allowPCC: pccAllowed)
            if await provider.isAvailable {
                agent.setProvider(provider)
                // Prewarm the actual session with tools for faster first response
                provider.prewarm(with: "Help me")
                return provider.name
            }
        }

        // Fall back to OpenRouter
        return setupOpenRouterProvider()
    }

    /// Check if a provider type is available
    func checkAvailability(_ providerType: LLMProviderType) async -> Bool {
        switch providerType {
        case .foundationModels:
            if #available(iOS 26.0, macOS 26.0, *) {
                let provider = FoundationModelsProvider()
                return await provider.isAvailable
            }
            return false
        case .openRouter:
            let apiKey = KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? ""
            return !apiKey.isEmpty
        }
    }

    /// Switch to a different provider, resetting agent state
    /// - Returns: The new provider display name
    func switchProvider(to providerType: LLMProviderType, appState: AppState?) async -> String {
        // Reset agent to clear any cached context from the previous provider
        await agent.resetForNewConversation()

        if let appState = appState {
            await appState.setProviderWithFallback(providerType) { type in
                await self.checkAvailability(type)
            }
            return await setupProvider(for: appState.selectedProvider, appState: appState)
        } else {
            return await setupProvider(for: providerType, appState: nil)
        }
    }

    /// Grant PCC consent and update user defaults
    func grantPCCConsent() {
        UserDefaults.standard.set(true, forKey: "pccConsentGiven")
    }

    /// Get an available LLM provider for auxiliary tasks (e.g., prompt enhancement)
    func getAvailableProvider() async -> (any LLMProvider)? {
        // Try Foundation Models first, but check availability
        if #available(iOS 26.0, macOS 26.0, *) {
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

    /// Format model name for display (e.g., "anthropic/claude-sonnet-4" -> "Claude Sonnet 4")
    func formatModelName(_ model: String) -> String {
        let parts = model.split(separator: "/")
        if parts.count == 2 {
            return String(parts[1]).replacingOccurrences(of: "-", with: " ").capitalized
        }
        return model
    }

    // MARK: - Private

    @discardableResult
    private func setupOpenRouterProvider() -> String {
        // Get API key from Keychain (secure storage)
        let apiKey = KeychainManager.shared.get(key: KeychainManager.Keys.openRouterApiKey) ?? ""
        let model = UserDefaults.standard.string(forKey: "selectedModel") ?? "anthropic/claude-sonnet-4"

        if !apiKey.isEmpty {
            let provider = OpenRouterProvider(apiKey: apiKey, model: model)
            agent.setProvider(provider)
            return "\(provider.name) (\(formatModelName(model)))"
        } else {
            return "No provider configured"
        }
    }
}
