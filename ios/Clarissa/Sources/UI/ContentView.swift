import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var showSettings = false
    @State private var showSessionHistory = false
    @State private var sessionCount: Int = 0

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
                        HStack(spacing: 12) {
                            newSessionButton
                            historyButton
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        titleView
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            voiceModeButton
                            settingsButton
                        }
                    }
                    #else
                    // macOS: Use navigation placement for leading items
                    ToolbarItem(placement: .navigation) {
                        HStack(spacing: 8) {
                            newSessionButton
                            historyButton
                        }
                    }

                    // macOS: Principal placement for title
                    ToolbarItem(placement: .principal) {
                        titleView
                    }

                    // macOS: Primary action for settings (right side)
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 8) {
                            voiceModeButton
                            settingsButton
                        }
                    }
                    #endif
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(onProviderChange: {
                        chatViewModel.refreshProvider()
                    })
                }
                .sheet(isPresented: $showSessionHistory, onDismiss: {
                    Task { await refreshSessionCount() }
                }) {
                    SessionHistoryView(viewModel: chatViewModel) {
                        showSessionHistory = false
                    }
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
                chatViewModel.showNewSessionConfirmation = false
            }
            Button("Start New", role: .destructive) {
                chatViewModel.startNewSession()
                Task { await refreshSessionCount() }
            }
        } message: {
            Text("Your current conversation will be saved to history.")
        }
    }

    private var titleView: some View {
        Text("Clarissa")
            .font(.headline.bold())
            .gradientForeground()
    }

    private var newSessionButton: some View {
        Button {
            chatViewModel.requestNewSession()
        } label: {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(ClarissaTheme.gradient)
        }
        .accessibilityLabel("New conversation")
        .accessibilityHint("Start a new conversation")
        #if os(macOS)
        .keyboardShortcut("n", modifiers: .command) // Cmd+N for new session
        #endif
    }

    private var historyButton: some View {
        Button {
            showSessionHistory = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(ClarissaTheme.gradient)

                // Session count badge (show if more than 1 session)
                if sessionCount > 1 {
                    Text("\(min(sessionCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(ClarissaTheme.pink)
                        .clipShape(Circle())
                        .offset(x: 8, y: -8)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel("Conversation history")
        .accessibilityHint(sessionCount > 1 ? "\(sessionCount) conversations" : "View past conversations")
        .task {
            await refreshSessionCount()
        }
    }

    private func refreshSessionCount() async {
        let sessions = await chatViewModel.getAllSessions()
        sessionCount = sessions.count
    }

    private var voiceModeButton: some View {
        Button {
            Task { await chatViewModel.toggleVoiceMode() }
        } label: {
            Image(systemName: chatViewModel.isVoiceModeActive ? "waveform.circle.fill" : "waveform.circle")
                .foregroundStyle(chatViewModel.isVoiceModeActive ? AnyShapeStyle(ClarissaTheme.pink) : AnyShapeStyle(ClarissaTheme.gradient))
                .symbolEffect(.bounce, value: chatViewModel.isVoiceModeActive)
        }
        .accessibilityLabel(chatViewModel.isVoiceModeActive ? "Exit voice mode" : "Enter voice mode")
        .accessibilityHint(chatViewModel.isVoiceModeActive ? "Tap to exit hands-free conversation" : "Tap to start hands-free conversation")
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gear")
                .foregroundStyle(ClarissaTheme.gradient)
        }
        .accessibilityLabel("Settings")
        .accessibilityHint("Configure app settings")
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

