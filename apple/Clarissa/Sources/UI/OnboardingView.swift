import SwiftUI
import EventKit
import Contacts
import CoreLocation
import Speech

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
            description: "Your intelligent AI assistant that helps you manage your day, answer questions, and get things done.",
            isPermissionsPage: false
        ),
        OnboardingPage(
            id: "ondevice",
            icon: "cpu",
            title: "On-Device AI",
            description: "Clarissa uses Apple Intelligence for private, on-device processing. Your conversations stay on your device.",
            isPermissionsPage: false
        ),
        OnboardingPage(
            id: "tools",
            icon: "wrench.and.screwdriver",
            title: "Powerful Tools",
            description: "Access your calendar, contacts, and more. Clarissa can help you schedule events, find contacts, and perform calculations.",
            isPermissionsPage: false
        ),
        OnboardingPage(
            id: "permissions",
            icon: "lock.shield",
            title: "Permissions",
            description: "Grant permissions to unlock Clarissa's full potential. All data stays on your device.",
            isPermissionsPage: true
        ),
        OnboardingPage(
            id: "memory",
            icon: "brain.head.profile",
            title: "Long-term Memory",
            description: "Clarissa remembers important information across conversations to provide personalized assistance.",
            isPermissionsPage: false
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
            // Page indicator for macOS - clickable dots
            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Button {
                        withAnimation(reduceMotion ? .none : .easeInOut) {
                            currentPage = index
                        }
                    } label: {
                        Circle()
                            .fill(index == currentPage ? ClarissaTheme.purple : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(index + 1) of \(pages.count)")
                    .accessibilityHint(index == currentPage ? "Current page" : "Double-tap to go to this page")
                }
            }
            .padding(.bottom, 8)
            #endif

            // Buttons with glass morphing on iOS/macOS 26+
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

    @ViewBuilder
    private func onboardingPageView(page: OnboardingPage, index: Int) -> some View {
        if page.isPermissionsPage {
            PermissionsPageView()
        } else {
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
    }

    // MARK: - Glass Buttons Section (iOS/macOS 26+)

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
            legacyGetStartedButton
        }
    }

    private var legacyGetStartedButton: some View {
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
            legacyContinueButton
        }
    }

    private var legacyContinueButton: some View {
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

private struct OnboardingPage {
    let id: String
    let icon: String
    let title: String
    let description: String
    var isPermissionsPage: Bool = false
}

// MARK: - Permissions Page View

private struct PermissionsPageView: View {
    @State private var calendarGranted = false
    @State private var contactsGranted = false
    @State private var locationGranted = false
    @State private var speechGranted = false
    @State private var remindersGranted = false

    private let eventStore = EKEventStore()
    private let contactStore = CNContactStore()
    private let locationManager = CLLocationManager()

    var body: some View {
        VStack(spacing: 16) {
            Text("Permissions")
                .font(.title.bold())
                .gradientForeground()

            Text("Grant access to unlock features. All data stays private on your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            ScrollView {
                VStack(spacing: 12) {
                    PermissionRow(
                        icon: "calendar",
                        title: "Calendar",
                        description: "Schedule and view events",
                        isGranted: calendarGranted,
                        onRequest: requestCalendarAccess
                    )

                    PermissionRow(
                        icon: "person.crop.circle",
                        title: "Contacts",
                        description: "Find contact information",
                        isGranted: contactsGranted,
                        onRequest: requestContactsAccess
                    )

                    PermissionRow(
                        icon: "checklist",
                        title: "Reminders",
                        description: "Create and manage reminders",
                        isGranted: remindersGranted,
                        onRequest: requestRemindersAccess
                    )

                    PermissionRow(
                        icon: "location",
                        title: "Location",
                        description: "Get weather for your area",
                        isGranted: locationGranted,
                        onRequest: requestLocationAccess
                    )

                    PermissionRow(
                        icon: "mic",
                        title: "Speech Recognition",
                        description: "Use voice commands",
                        isGranted: speechGranted,
                        onRequest: requestSpeechAccess
                    )
                }
                .padding(.horizontal, 24)
            }

            Text("You can change these later in Settings")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            checkPermissions()
        }
    }

    private func checkPermissions() {
        // Check calendar
        let calendarStatus = EKEventStore.authorizationStatus(for: .event)
        calendarGranted = calendarStatus == .fullAccess

        // Check contacts
        let contactsStatus = CNContactStore.authorizationStatus(for: .contacts)
        contactsGranted = contactsStatus == .authorized

        // Check reminders
        let remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        remindersGranted = remindersStatus == .fullAccess

        // Check location
        let locationStatus = locationManager.authorizationStatus
        #if os(macOS)
        locationGranted = locationStatus == .authorized || locationStatus == .authorizedAlways
        #else
        locationGranted = locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
        #endif

        // Check speech
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        speechGranted = speechStatus == .authorized
    }

    private func requestCalendarAccess() {
        Task {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                await MainActor.run { calendarGranted = granted }
            } catch {
                // Handle error silently
            }
        }
    }

    private func requestContactsAccess() {
        Task {
            do {
                let granted = try await contactStore.requestAccess(for: .contacts)
                await MainActor.run { contactsGranted = granted }
            } catch {
                // Handle error silently
            }
        }
    }

    private func requestRemindersAccess() {
        Task {
            do {
                let granted = try await eventStore.requestFullAccessToReminders()
                await MainActor.run { remindersGranted = granted }
            } catch {
                // Handle error silently
            }
        }
    }

    private func requestLocationAccess() {
        locationManager.requestWhenInUseAuthorization()
        // Check again after a delay
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run { checkPermissions() }
        }
    }

    private func requestSpeechAccess() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                speechGranted = status == .authorized
            }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(ClarissaTheme.gradient)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow") {
                    HapticManager.shared.lightTap()
                    onRequest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(description), \(isGranted ? "granted" : "not granted")")
        .accessibilityHint(isGranted ? "" : "Double-tap to request permission")
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}

