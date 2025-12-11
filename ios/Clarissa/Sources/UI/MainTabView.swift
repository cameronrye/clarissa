import SwiftUI

/// Main tab-based navigation for Clarissa with iOS 26 Liquid Glass tab bar
/// Uses tabBarMinimizeBehavior for modern scrolling experience
public struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var selectedTab: ClarissaTab = .chat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            modernTabView
        } else {
            ContentView()
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var modernTabView: some View {
        TabView(selection: $selectedTab) {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right", value: .chat) {
                ChatTabContent(viewModel: chatViewModel)
            }

            Tab("History", systemImage: "clock.arrow.circlepath", value: .history) {
                HistoryTabContent(viewModel: chatViewModel)
            }

            Tab("Settings", systemImage: "gear", value: .settings) {
                SettingsTabContent()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(ClarissaTheme.purple)
        .onChange(of: selectedTab) { _, _ in
            HapticManager.shared.selection()
        }
        .onAppear {
            chatViewModel.configure(with: appState)
        }
        .onChange(of: appState.selectedProvider) { _, newValue in
            Task {
                await chatViewModel.switchProvider(to: newValue)
            }
        }
    }
}

enum ClarissaTab: Hashable {
    case chat
    case history
    case settings
}

@available(iOS 26.0, macOS 26.0, *)
struct ChatTabContent: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var showContextDetails = false
    @Namespace private var chatNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ChatView(viewModel: viewModel)
                .navigationTitle("Clarissa")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        titleView
                    }
                    #if os(iOS)
                    ToolbarItem(placement: .topBarTrailing) {
                        toolbarButtons
                    }
                    #else
                    ToolbarItem(placement: .primaryAction) {
                        toolbarButtons
                    }
                    #endif
                }
                .sheet(isPresented: $showContextDetails) {
                    ContextDetailSheet(stats: viewModel.contextStats)
                        .presentationDetents([.medium, .large])
                        .scrollContentBackground(.hidden)
                }
        }
        .alert("Start New Conversation?", isPresented: $viewModel.showNewSessionConfirmation) {
            Button("Cancel", role: .cancel) {
                HapticManager.shared.lightTap()
                viewModel.showNewSessionConfirmation = false
            }
            Button("Start New", role: .destructive) {
                HapticManager.shared.warning()
                viewModel.startNewSession()
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
            if viewModel.contextStats.messageCount > 0 {
                ContextIndicatorView(stats: viewModel.contextStats) {
                    showContextDetails = true
                }
            }
        }
    }

    private var toolbarButtons: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 12) {
                Button {
                    HapticManager.shared.lightTap()
                    viewModel.requestNewSession()
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title3)
                }
                .glassEffect(reduceMotion ? .regular : .regular.interactive(), in: .circle)
                .glassEffectID("newSession", in: chatNamespace)
                .accessibilityLabel("New conversation")
                .accessibilityHint("Double-tap to start a new conversation")

                Button {
                    HapticManager.shared.mediumTap()
                    Task { await viewModel.toggleVoiceMode() }
                } label: {
                    Image(systemName: viewModel.isVoiceModeActive ? "waveform.circle.fill" : "waveform.circle")
                        .font(.title3)
                        .symbolEffect(.bounce, value: viewModel.isVoiceModeActive)
                }
                .glassEffect(
                    reduceMotion
                        ? .regular.tint(viewModel.isVoiceModeActive ? ClarissaTheme.pink : nil)
                        : .regular.tint(viewModel.isVoiceModeActive ? ClarissaTheme.pink : nil).interactive(),
                    in: .circle
                )
                .glassEffectID("voiceMode", in: chatNamespace)
                .accessibilityLabel(viewModel.isVoiceModeActive ? "Exit voice mode" : "Enter voice mode")
            }
        }
    }
}


// MARK: - History Tab Content

@available(iOS 26.0, macOS 26.0, *)
struct HistoryTabContent: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var sessions: [Session] = []
    @State private var currentSessionId: UUID?

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your conversations will appear here.")
                    )
                } else {
                    ForEach(sessions) { session in
                        SessionRowView(
                            session: session,
                            isCurrentSession: session.id == currentSessionId,
                            onTap: {
                                HapticManager.shared.lightTap()
                                Task {
                                    await viewModel.switchToSession(id: session.id)
                                }
                            }
                        )
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
            .navigationTitle("History")
            .refreshable {
                await loadData()
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        sessions = await viewModel.getAllSessions()
        currentSessionId = await viewModel.getCurrentSessionId()
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            Task {
                await viewModel.deleteSession(id: session.id)
            }
        }
        sessions.remove(atOffsets: offsets)
    }
}

// MARK: - Settings Tab Content

@available(iOS 26.0, macOS 26.0, *)
struct SettingsTabContent: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        SettingsView(onProviderChange: nil)
    }
}

#Preview {
    MainTabView()
        .environmentObject(AppState())
}