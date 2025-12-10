import SwiftUI

public struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0

    public init() {}

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "sparkles",
            title: "Welcome to Clarissa",
            description: "Your intelligent AI assistant that helps you manage your day, answer questions, and get things done."
        ),
        OnboardingPage(
            icon: "cpu",
            title: "On-Device AI",
            description: "Clarissa uses Apple Intelligence for private, on-device processing. Your conversations stay on your device."
        ),
        OnboardingPage(
            icon: "wrench.and.screwdriver",
            title: "Powerful Tools",
            description: "Access your calendar, contacts, and more. Clarissa can help you schedule events, find contacts, and perform calculations."
        ),
        OnboardingPage(
            icon: "brain.head.profile",
            title: "Long-term Memory",
            description: "Clarissa remembers important information across conversations to provide personalized assistance."
        )
    ]

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: page.icon)
                            .font(.system(size: 80))
                            .foregroundStyle(ClarissaTheme.gradient)

                        Text(page.title)
                            .font(.title.bold())
                            .gradientForeground()
                            .multilineTextAlignment(.center)

                        Text(page.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif
            
            VStack(spacing: 16) {
                if currentPage == pages.count - 1 {
                    Button {
                        appState.completeOnboarding()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(ClarissaTheme.gradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(ClarissaTheme.gradient)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        appState.completeOnboarding()
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}

