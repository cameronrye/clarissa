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

    // MARK: - Glass Buttons Section (iOS/macOS 26+)
    // Skip button removed entirely per App Store guideline 5.1.1
    // Users must proceed through all onboarding pages including permissions

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
    @State private var isRequestingPermission = false
    @State private var requestingPermissionType: String?

    // Use StateObject for the location delegate to properly handle callbacks
    @StateObject private var locationDelegate = LocationPermissionDelegate()

    // Use static instances to avoid recreating on every view update
    private static let eventStore = EKEventStore()
    private static let contactStore = CNContactStore()

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
                        isLoading: requestingPermissionType == "calendar",
                        onRequest: requestCalendarAccess
                    )

                    PermissionRow(
                        icon: "person.crop.circle",
                        title: "Contacts",
                        description: "Find contact information",
                        isGranted: contactsGranted,
                        isLoading: requestingPermissionType == "contacts",
                        onRequest: requestContactsAccess
                    )

                    PermissionRow(
                        icon: "checklist",
                        title: "Reminders",
                        description: "Create and manage reminders",
                        isGranted: remindersGranted,
                        isLoading: requestingPermissionType == "reminders",
                        onRequest: requestRemindersAccess
                    )

                    PermissionRow(
                        icon: "location",
                        title: "Location",
                        description: "Get weather for your area",
                        isGranted: locationGranted,
                        isLoading: requestingPermissionType == "location",
                        onRequest: requestLocationAccess
                    )

                    PermissionRow(
                        icon: "mic",
                        title: "Speech Recognition",
                        description: "Use voice commands",
                        isGranted: speechGranted,
                        isLoading: requestingPermissionType == "speech",
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
            locationDelegate.onAuthorizationChanged = { status in
                updateLocationStatus(status)
            }
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

        // Check location using delegate's manager
        let locationStatus = locationDelegate.locationManager.authorizationStatus
        #if os(macOS)
        locationGranted = locationStatus == .authorized || locationStatus == .authorizedAlways
        #else
        locationGranted = locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
        #endif

        // Check speech
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        speechGranted = speechStatus == .authorized
    }

    private func updateLocationStatus(_ status: CLAuthorizationStatus) {
        requestingPermissionType = nil
        #if os(macOS)
        locationGranted = status == .authorized || status == .authorizedAlways
        #else
        locationGranted = status == .authorizedWhenInUse || status == .authorizedAlways
        #endif
    }

    private func requestCalendarAccess() {
        requestingPermissionType = "calendar"
        Task {
            do {
                let granted = try await Self.eventStore.requestFullAccessToEvents()
                await MainActor.run {
                    calendarGranted = granted
                    requestingPermissionType = nil
                }
            } catch {
                await MainActor.run { requestingPermissionType = nil }
                ClarissaLogger.ui.error("Calendar permission request failed: \(error.localizedDescription)")
            }
        }
    }

    private func requestContactsAccess() {
        requestingPermissionType = "contacts"
        Task {
            do {
                let granted = try await Self.contactStore.requestAccess(for: .contacts)
                await MainActor.run {
                    contactsGranted = granted
                    requestingPermissionType = nil
                }
            } catch {
                await MainActor.run { requestingPermissionType = nil }
                ClarissaLogger.ui.error("Contacts permission request failed: \(error.localizedDescription)")
            }
        }
    }

    private func requestRemindersAccess() {
        requestingPermissionType = "reminders"
        Task {
            do {
                let granted = try await Self.eventStore.requestFullAccessToReminders()
                await MainActor.run {
                    remindersGranted = granted
                    requestingPermissionType = nil
                }
            } catch {
                await MainActor.run { requestingPermissionType = nil }
                ClarissaLogger.ui.error("Reminders permission request failed: \(error.localizedDescription)")
            }
        }
    }

    private func requestLocationAccess() {
        requestingPermissionType = "location"
        locationDelegate.locationManager.requestWhenInUseAuthorization()
    }

    private func requestSpeechAccess() {
        requestingPermissionType = "speech"
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                speechGranted = status == .authorized
                requestingPermissionType = nil
            }
        }
    }
}

// MARK: - Location Permission Delegate

private class LocationPermissionDelegate: NSObject, ObservableObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    var onAuthorizationChanged: ((CLAuthorizationStatus) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChanged?(manager.authorizationStatus)
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    var isLoading: Bool = false
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
                    .transition(.scale.combined(with: .opacity))
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            } else {
                Button("Continue") {
                    HapticManager.shared.lightTap()
                    onRequest()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: isGranted)
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(description), \(isGranted ? "granted" : isLoading ? "requesting" : "not granted")")
        .accessibilityHint(isGranted || isLoading ? "" : "Double-tap to request permission")
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}

