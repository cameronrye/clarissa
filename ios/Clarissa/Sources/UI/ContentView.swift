import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var showSettings = false
    @State private var showSessionHistory = false
    @State private var showContextDetails = false

    // Namespace for glass morphing transitions
    @Namespace private var toolbarNamespace
    // Namespace for zoom navigation transitions
    @Namespace private var zoomNamespace

    // Accessibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        NavigationStack {
            ChatView(viewModel: chatViewModel)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        leadingToolbarContent
                    }

                    ToolbarItem(placement: .principal) {
                        titleView
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        trailingToolbarContent
                    }
                    #else
                    // macOS: Use navigation placement for leading items
                    ToolbarItem(placement: .navigation) {
                        leadingToolbarContent
                    }

                    // macOS: Principal placement for title
                    ToolbarItem(placement: .principal) {
                        titleView
                    }

                    // macOS: Primary action for settings (right side)
                    ToolbarItem(placement: .primaryAction) {
                        trailingToolbarContent
                    }
                    #endif
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(onProviderChange: {
                        chatViewModel.refreshProvider()
                    })
                    .presentationDetents([.large])
                    .scrollContentBackground(.hidden)  // Glass compatibility
                }
                .sheet(isPresented: $showSessionHistory) {
                    SessionHistoryView(viewModel: chatViewModel) {
                        showSessionHistory = false
                    }
                    .presentationDetents([.medium, .large])
                    .scrollContentBackground(.hidden)  // Glass compatibility
                }
                .sheet(isPresented: $showContextDetails) {
                    ContextDetailSheet(stats: chatViewModel.contextStats)
                        .presentationDetents([.medium, .large])
                        .scrollContentBackground(.hidden)  // Glass compatibility
                }
        }
        .tint(ClarissaTheme.purple)
        .onAppear {
            chatViewModel.configure(with: appState)
        }
        .onChange(of: appState.selectedProvider) { _, newValue in
            Task {
                await chatViewModel.switchProvider(to: newValue)
            }
        }
        .alert("Start New Conversation?", isPresented: $chatViewModel.showNewSessionConfirmation) {
            Button("Cancel", role: .cancel) {
                HapticManager.shared.lightTap()
                chatViewModel.showNewSessionConfirmation = false
            }
            Button("Start New", role: .destructive) {
                HapticManager.shared.warning()
                chatViewModel.startNewSession()
            }
        } message: {
            Text("Your current conversation will be saved to history.")
        }
    }

    private var titleView: some View {
        HStack(spacing: 8) {
            Text("Clarissa")
                .font(.headline.bold())
                .gradientForeground()

            // Show context indicator when there are messages
            if chatViewModel.contextStats.messageCount > 0 {
                ContextIndicatorView(stats: chatViewModel.contextStats) {
                    showContextDetails = true
                }
            }
        }
    }

    // MARK: - Toolbar Content with GlassEffectContainer

    @ViewBuilder
    private var leadingToolbarContent: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 12) {
                    newSessionButton
                    historyButton
                }
            }
        } else {
            HStack(spacing: 12) {
                newSessionButton
                historyButton
            }
        }
    }

    @ViewBuilder
    private var trailingToolbarContent: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: 12) {
                    voiceModeButton
                    settingsButton
                }
            }
        } else {
            HStack(spacing: 12) {
                voiceModeButton
                settingsButton
            }
        }
    }

    @ViewBuilder
    private var newSessionButton: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button {
                HapticManager.shared.lightTap()
                chatViewModel.requestNewSession()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
            }
            .glassEffect(reduceMotion ? .regular : .regular.interactive(), in: .circle)
            .glassEffectID("newSession", in: toolbarNamespace)
            .accessibilityLabel("New conversation")
            .accessibilityHint("Double-tap to start a new conversation. Current conversation will be saved.")
            #if os(macOS)
            .keyboardShortcut("n", modifiers: .command)
            #endif
        } else {
            Button {
                HapticManager.shared.lightTap()
                chatViewModel.requestNewSession()
            } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(ClarissaTheme.gradient)
            }
            .accessibilityLabel("New conversation")
            .accessibilityHint("Double-tap to start a new conversation. Current conversation will be saved.")
            #if os(macOS)
            .keyboardShortcut("n", modifiers: .command)
            #endif
        }
    }

    @ViewBuilder
    private var historyButton: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button {
                HapticManager.shared.lightTap()
                showSessionHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
            }
            .glassEffect(reduceMotion ? .regular : .regular.interactive(), in: .circle)
            .glassEffectID("history", in: toolbarNamespace)
            .accessibilityLabel("Conversation history")
            .accessibilityHint("Double-tap to browse and switch between past conversations")
        } else {
            Button {
                HapticManager.shared.lightTap()
                showSessionHistory = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(ClarissaTheme.gradient)
            }
            .accessibilityLabel("Conversation history")
            .accessibilityHint("Double-tap to browse and switch between past conversations")
        }
    }

    @ViewBuilder
    private var voiceModeButton: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button {
                HapticManager.shared.mediumTap()
                Task { await chatViewModel.toggleVoiceMode() }
            } label: {
                Image(systemName: chatViewModel.isVoiceModeActive ? "waveform.circle.fill" : "waveform.circle")
                    .font(.title3)
                    .symbolEffect(.bounce, value: chatViewModel.isVoiceModeActive)
            }
            .glassEffect(
                reduceMotion
                    ? .regular.tint(chatViewModel.isVoiceModeActive ? ClarissaTheme.pink : nil)
                    : .regular.tint(chatViewModel.isVoiceModeActive ? ClarissaTheme.pink : nil).interactive(),
                in: .circle
            )
            .glassEffectID("voiceMode", in: toolbarNamespace)
            .animation(.bouncy, value: chatViewModel.isVoiceModeActive)
            .accessibilityLabel(chatViewModel.isVoiceModeActive ? "Exit voice mode" : "Enter voice mode")
            .accessibilityHint(chatViewModel.isVoiceModeActive ? "Double-tap to exit hands-free conversation and return to text input" : "Double-tap to start hands-free voice conversation")
        } else {
            Button {
                HapticManager.shared.mediumTap()
                Task { await chatViewModel.toggleVoiceMode() }
            } label: {
                Image(systemName: chatViewModel.isVoiceModeActive ? "waveform.circle.fill" : "waveform.circle")
                    .foregroundStyle(chatViewModel.isVoiceModeActive ? AnyShapeStyle(ClarissaTheme.pink) : AnyShapeStyle(ClarissaTheme.gradient))
                    .symbolEffect(.bounce, value: chatViewModel.isVoiceModeActive)
            }
            .accessibilityLabel(chatViewModel.isVoiceModeActive ? "Exit voice mode" : "Enter voice mode")
            .accessibilityHint(chatViewModel.isVoiceModeActive ? "Double-tap to exit hands-free conversation and return to text input" : "Double-tap to start hands-free voice conversation")
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Button {
                HapticManager.shared.lightTap()
                showSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.title3)
            }
            .glassEffect(reduceMotion ? .regular : .regular.interactive(), in: .circle)
            .glassEffectID("settings", in: toolbarNamespace)
            .accessibilityLabel("Settings")
            .accessibilityHint("Double-tap to configure LLM provider, tools, voice, and memory settings")
        } else {
            Button {
                HapticManager.shared.lightTap()
                showSettings = true
            } label: {
                Image(systemName: "gear")
                    .foregroundStyle(ClarissaTheme.gradient)
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Double-tap to configure LLM provider, tools, voice, and memory settings")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

