import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: "onboardingComplete")
    @Published public var selectedProvider: LLMProviderType = .foundationModels
    
    public init() {}
    
    public func completeOnboarding() {
        isOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
    }
}

public enum LLMProviderType: String, CaseIterable, Identifiable, Sendable {
    case foundationModels = "On-Device (Apple Intelligence)"
    case openRouter = "OpenRouter (Cloud)"
    
    public var id: String { rawValue }
}

