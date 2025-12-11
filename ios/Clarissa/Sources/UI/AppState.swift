import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "onboardingComplete")
    @Published public var selectedProvider: LLMProviderType {
        didSet {
            // Persist provider selection
            UserDefaults.standard.set(selectedProvider.rawValue, forKey: Self.providerKey)
        }
    }

    private static let providerKey = "selectedProviderType"

    public init() {
        // Load persisted provider selection with fallback to default
        if let savedRaw = UserDefaults.standard.string(forKey: Self.providerKey),
           let savedProvider = LLMProviderType(rawValue: savedRaw) {
            self.selectedProvider = savedProvider
        } else {
            self.selectedProvider = .foundationModels
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

