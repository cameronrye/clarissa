import SwiftUI

public struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0

    // Namespace for glass morphing transitions between pages
    @Namespace private var onboardingNamespace

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome",
            icon: "sparkles",
            title: "Welcome to Clarissa",
            description: "Your intelligent AI assistant that helps you manage your day, answer questions, and get things done."
        ),
        OnboardingPage(
            id: "ondevice",
            icon: "cpu",
            title: "On-Device AI",
            description: "Clarissa uses Apple Intelligence for private, on-device processing. Your conversations stay on your device."
        ),
        OnboardingPage(
            id: "tools",
            icon: "wrench.and.screwdriver",
            title: "Powerful Tools",
            description: "Access your calendar, contacts, and more. Clarissa can help you schedule events, find contacts, and perform calculations."
        ),
        OnboardingPage(
            id: "memory",
            icon: "brain.head.profile",
            title: "Long-term Memory",
            description: "Clarissa remembers important information across conversations to provide personalized assistance."
        )
    ]

    public var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    onboardingPageView(page: page, index: index)
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #else
            .tabViewStyle(.automatic)
            #endif
            .onChange(of: currentPage) { _, _ in
                HapticManager.shared.selection()
            }

            #if os(macOS)
            // Page indicator for macOS
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? ClarissaTheme.purple : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 8)
            #endif

            // Buttons with glass morphing on iOS 26+
            if #available(iOS 26.0, macOS 26.0, *) {
                glassButtonsSection
            } else {
                legacyButtonsSection
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Onboarding, page \(currentPage + 1) of \(pages.count)")
    }

    // MARK: - Page Content

    private func onboardingPageView(page: OnboardingPage, index: Int) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(ClarissaTheme.gradient)
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title). \(page.description)")
    }

    // MARK: - Glass Buttons Section (iOS 26+)

    @available(iOS 26.0, macOS 26.0, *)
    private var glassButtonsSection: some View {
        GlassEffectContainer(spacing: 20) {
            VStack(spacing: 16) {
                if currentPage == pages.count - 1 {
                    getStartedButton
                        .glassEffectID("primaryButton", in: onboardingNamespace)
                } else {
                    continueButton
                        .glassEffectID("primaryButton", in: onboardingNamespace)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Legacy Buttons Section

    private var legacyButtonsSection: some View {
        VStack(spacing: 16) {
            if currentPage == pages.count - 1 {
                getStartedButton
            } else {
                continueButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Button Components with Glass Effects

    @ViewBuilder
    private var getStartedButton: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button {
                HapticManager.shared.success()
                appState.completeOnboarding()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .tint(ClarissaTheme.purple)
            .accessibilityLabel("Get Started")
            .accessibilityHint("Double-tap to complete onboarding and start using Clarissa")
        } else {
            Button {
                HapticManager.shared.success()
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
            .accessibilityLabel("Get Started")
            .accessibilityHint("Double-tap to complete onboarding and start using Clarissa")
        }
    }

    @ViewBuilder
    private var continueButton: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button {
                HapticManager.shared.lightTap()
                withAnimation(reduceMotion ? .none : .bouncy) {
                    currentPage += 1
                }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .tint(ClarissaTheme.purple)
            .accessibilityLabel("Continue")
            .accessibilityHint("Double-tap to go to the next page")
        } else {
            Button {
                HapticManager.shared.lightTap()
                withAnimation(reduceMotion ? .none : .easeInOut) {
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
            .accessibilityLabel("Continue")
            .accessibilityHint("Double-tap to go to the next page")
        }
    }
}

private struct OnboardingPage {
    let id: String
    let icon: String
    let title: String
    let description: String
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}

