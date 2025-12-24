import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Main navigation for Clarissa
/// - iPhone: Tab-based navigation with iOS 26 Liquid Glass tab bar
/// - iPad/macOS: NavigationSplitView with sidebar for history
public struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var selectedTab: ClarissaTab = .chat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init() {}

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            adaptiveNavigation
        } else {
            ContentView()
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    @ViewBuilder
    private var adaptiveNavigation: some View {
        #if os(macOS)
        // macOS always uses split view
        splitViewNavigation
        #else
        // iOS: Use split view on iPad, tabs on iPhone
        if horizontalSizeClass == .regular {
            splitViewNavigation
        } else {
            tabViewNavigation
        }
        #endif
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var splitViewNavigation: some View {
        NavigationSplitView {
            SidebarView(viewModel: chatViewModel, selectedTab: $selectedTab)
        } detail: {
            switch selectedTab {
            case .chat:
                ChatTabContent(viewModel: chatViewModel)
            case .history:
                // History is shown in sidebar, show chat as detail
                ChatTabContent(viewModel: chatViewModel)
            case .settings:
                SettingsTabContent()
            }
        }
        .tint(ClarissaTheme.purple)
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 600)
        #endif
        .onAppear {
            chatViewModel.configure(with: appState)
        }
        .onChange(of: appState.selectedProvider) { _, newValue in
            Task {
                await chatViewModel.switchProvider(to: newValue)
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private var tabViewNavigation: some View {
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
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
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

// MARK: - Sidebar View for iPad/macOS

@available(iOS 26.0, macOS 26.0, *)
struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var selectedTab: ClarissaTab
    @State private var sessions: [Session] = []
    @State private var currentSessionId: UUID?
    @State private var sessionToDelete: Session?
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            chatSection
            historySection
            settingsSection
        }
        .navigationTitle("Clarissa")
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 250, ideal: 300, max: 400)
        #endif
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .alert("Delete Conversation", isPresented: $showDeleteConfirmation, presenting: sessionToDelete) { session in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteSession(id: session.id)
                    sessions.removeAll { $0.id == session.id }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
    }

    // MARK: - Sections

    private var chatSection: some View {
        Section {
            Button {
                HapticManager.shared.lightTap()
                viewModel.requestNewSession()
                selectedTab = .chat
            } label: {
                Label("New Chat", systemImage: "plus.circle")
            }
        }
    }

    private var historySection: some View {
        Section("Recent Conversations") {
            ForEach(Array(sessions.prefix(10))) { session in
                sessionRow(for: session)
            }
            .onDelete(perform: deleteSessions)

            viewAllLink
        }
    }

    @ViewBuilder
    private func sessionRow(for session: Session) -> some View {
        SessionSidebarRow(
            session: session,
            isCurrentSession: session.id == currentSessionId
        ) {
            HapticManager.shared.lightTap()
            Task {
                await viewModel.switchToSession(id: session.id)
                selectedTab = .chat
            }
        }
    }

    @ViewBuilder
    private var viewAllLink: some View {
        if sessions.count > 10 {
            NavigationLink {
                HistoryTabContent(viewModel: viewModel)
            } label: {
                Label("View All (\(sessions.count))", systemImage: "clock.arrow.circlepath")
            }
        }
    }

    private var settingsSection: some View {
        Section {
            Button {
                HapticManager.shared.lightTap()
                selectedTab = .settings
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }

    // MARK: - Helpers

    private func loadData() async {
        sessions = await viewModel.getAllSessions()
        currentSessionId = await viewModel.getCurrentSessionId()
    }

    private func deleteSessions(at offsets: IndexSet) {
        // Only handle single deletion with confirmation
        guard let firstIndex = offsets.first else { return }
        sessionToDelete = sessions[firstIndex]
        showDeleteConfirmation = true
    }
}

// MARK: - Session Sidebar Row

@available(iOS 26.0, macOS 26.0, *)
struct SessionSidebarRow: View {
    let session: Session
    let isCurrentSession: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.subheadline)
                        .fontWeight(isCurrentSession ? .semibold : .regular)
                        .lineLimit(1)

                    Text(session.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isCurrentSession {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ClarissaTheme.purple)
                        .font(.caption)
                }
            }
            #if os(macOS)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            #endif
        }
        .buttonStyle(.plain)
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
    @State private var showShareSheet = false
    @State private var exportedText = ""
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
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        contextIndicator
                    }
                    #else
                    ToolbarItem(placement: .navigation) {
                        contextIndicator
                    }
                    #endif

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
                #if os(iOS)
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(items: [exportedText])
                }
                #endif
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: .newConversation)) { _ in
                    viewModel.requestNewSession()
                }
                .onReceive(NotificationCenter.default.publisher(for: .clearConversation)) { _ in
                    viewModel.startNewSession()
                }
                #endif
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

    private func exportConversation() {
        exportedText = viewModel.exportConversation()
        #if os(iOS)
        showShareSheet = true
        #else
        // On macOS, copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(exportedText, forType: .string)
        #endif
    }

    private var titleView: some View {
        Text("Clarissa")
            .font(.headline.bold())
            .gradientForeground()
    }

    @ViewBuilder
    private var contextIndicator: some View {
        if viewModel.contextStats.messageCount > 0 {
            ContextIndicatorView(stats: viewModel.contextStats) {
                showContextDetails = true
            }
        }
    }

    private var toolbarButtons: some View {
        GlassEffectContainer(spacing: 20) {
            HStack(spacing: 12) {
                // Share/Export button - only show when there are messages
                if !viewModel.messages.isEmpty {
                    Button {
                        HapticManager.shared.lightTap()
                        exportConversation()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                    }
                    .glassEffect(reduceMotion ? .regular : .regular.interactive(), in: .circle)
                    .glassEffectID("export", in: chatNamespace)
                    .accessibilityLabel("Export conversation")
                    .accessibilityHint("Double-tap to share or copy this conversation")
                }

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

// MARK: - Share Sheet for iOS

#if os(iOS)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif


// MARK: - History Tab Content

@available(iOS 26.0, macOS 26.0, *)
struct HistoryTabContent: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var sessions: [Session] = []
    @State private var currentSessionId: UUID?
    @State private var sessionToDelete: Session?
    @State private var showDeleteConfirmation = false
    @State private var searchText = ""

    /// Filtered sessions based on search text
    private var filteredSessions: [Session] {
        if searchText.isEmpty {
            return sessions
        }
        let query = searchText.lowercased()
        return sessions.filter { session in
            session.title.lowercased().contains(query) ||
            session.messages.contains { msg in
                msg.content.lowercased().contains(query)
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your conversations will appear here.")
                    )
                } else if filteredSessions.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ForEach(filteredSessions) { session in
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
            .searchable(text: $searchText, prompt: "Search conversations")
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
        .alert("Delete Conversation", isPresented: $showDeleteConfirmation, presenting: sessionToDelete) { session in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteSession(id: session.id)
                    sessions.removeAll { $0.id == session.id }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
    }

    private func loadData() async {
        sessions = await viewModel.getAllSessions()
        currentSessionId = await viewModel.getCurrentSessionId()
    }

    private func deleteSessions(at offsets: IndexSet) {
        // Map filtered indices back to original sessions
        let sessionsToDelete = offsets.compactMap { index -> Session? in
            guard index < filteredSessions.count else { return nil }
            return filteredSessions[index]
        }
        guard let session = sessionsToDelete.first else { return }
        sessionToDelete = session
        showDeleteConfirmation = true
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