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
        // Floating liquid glass tab bar (iOS 26 default)
        // Tab bar collapses on scroll and floats above content
        // Note: When keyboard is visible, swipe down on keyboard to dismiss to access tab bar
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
            isCurrentSession: session.id == currentSessionId,
            onTap: {
                HapticManager.shared.lightTap()
                Task {
                    await viewModel.switchToSession(id: session.id)
                    selectedTab = .chat
                }
            },
            onDelete: {
                sessionToDelete = session
                showDeleteConfirmation = true
            }
        )
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
    var onDelete: (() -> Void)? = nil
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
        #if os(macOS)
        .contextMenu {
            if let onDelete = onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        #endif
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
    @EnvironmentObject var appState: AppState
    @State private var showContextDetails = false
    @State private var showShareSheet = false
    @State private var showHistorySheet = false
    @State private var showSettingsSheet = false
    @State private var showToolsSheet = false
    @State private var exportedText = ""
    @Namespace private var chatNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ChatView(viewModel: viewModel)
                #if os(iOS)
                .navigationTitle("Clarissa")
                .navigationBarTitleDisplayMode(.inline)
                #else
                .navigationTitle("")
                #endif
                .toolbar {
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        leadingToolbarItems
                    }

                    ToolbarItem(placement: .principal) {
                        titleView
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        trailingToolbarItems
                    }
                    #else
                    ToolbarItem(placement: .navigation) {
                        leadingToolbarItems
                    }

                    ToolbarItem(placement: .principal) {
                        titleView
                    }
                    .sharedBackgroundVisibility(.hidden)

                    ToolbarItem(placement: .primaryAction) {
                        trailingToolbarItems
                    }
                    #endif
                }
                .sheet(isPresented: $showContextDetails) {
                    ContextDetailSheet(stats: viewModel.contextStats)
                        .presentationDetents([.medium, .large])
                        .scrollContentBackground(.hidden)
                }
                .sheet(isPresented: $showToolsSheet) {
                    ToolSettingsView {
                        showToolsSheet = false
                    }
                    .environmentObject(appState)
                    .presentationDetents([.medium, .large])
                    .scrollContentBackground(.hidden)
                }
                #if os(iOS)
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(items: [exportedText])
                }
                .sheet(isPresented: $showHistorySheet) {
                    SessionHistoryView(viewModel: viewModel) {
                        showHistorySheet = false
                    }
                    .presentationDetents([.medium, .large])
                    .scrollContentBackground(.hidden)
                }
                .sheet(isPresented: $showSettingsSheet) {
                    SettingsView(onProviderChange: {
                        viewModel.refreshProvider()
                    })
                    .presentationDetents([.large])
                    .scrollContentBackground(.hidden)
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

    // MARK: - Leading Toolbar (Context Indicator)

    @ViewBuilder
    private var leadingToolbarItems: some View {
        contextIndicator
    }

    // MARK: - Trailing Toolbar (Overflow Menu)

    private var trailingToolbarItems: some View {
        Menu {
            // New conversation
            Button {
                HapticManager.shared.lightTap()
                viewModel.requestNewSession()
            } label: {
                Label("New Chat", systemImage: "plus.circle")
            }

            // Voice mode toggle
            Button {
                HapticManager.shared.mediumTap()
                Task { await viewModel.toggleVoiceMode() }
            } label: {
                Label(
                    viewModel.isVoiceModeActive ? "Exit Voice Mode" : "Voice Mode",
                    systemImage: viewModel.isVoiceModeActive ? "waveform.circle.fill" : "waveform.circle"
                )
            }

            Divider()

            // History (iOS only - macOS has sidebar)
            #if os(iOS)
            Button {
                HapticManager.shared.lightTap()
                showHistorySheet = true
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            #endif

            // Tools
            Button {
                HapticManager.shared.lightTap()
                showToolsSheet = true
            } label: {
                Label("Tools", systemImage: "wrench.and.screwdriver")
            }

            // Settings (iOS only - macOS has sidebar and menu bar)
            #if os(iOS)
            Button {
                HapticManager.shared.lightTap()
                showSettingsSheet = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
            #endif

            // Share/Export - only when there are messages
            if !viewModel.messages.isEmpty {
                Divider()

                Button {
                    HapticManager.shared.lightTap()
                    exportConversation()
                } label: {
                    Label("Share Conversation", systemImage: "square.and.arrow.up.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: 36, height: 36)
        .contentShape(Circle())
        .glassEffect(reduceMotion ? .regular : .regular.interactive(), in: .circle)
        .glassEffectID("overflow", in: chatNamespace)
        .accessibilityLabel("More options")
        .accessibilityHint("Double-tap for new chat, voice mode, history, tools, settings, and share")
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
    @State private var searchText = ""
    @State private var sessionToDelete: Session?
    @State private var showDeleteAlert = false
    #if os(iOS)
    @State private var editMode: EditMode = .inactive
    @State private var selectedSessions: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    #endif

    private var isEditing: Bool {
        #if os(iOS)
        return editMode == .active
        #else
        return false
        #endif
    }

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
            historyList
        }
        .task {
            await loadData()
        }
        .alert("Delete Conversation", isPresented: $showDeleteAlert, presenting: sessionToDelete) { session in
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteSession(id: session.id)
                    sessions.removeAll { $0.id == session.id }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Are you sure you want to delete this conversation? This action cannot be undone.")
        }
        #if os(iOS)
        .onChange(of: editMode) { _, newMode in
            if newMode == .inactive {
                selectedSessions.removeAll()
            }
        }
        .confirmationDialog(
            "Delete \(selectedSessions.count) Conversation\(selectedSessions.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        #endif
    }

    @ViewBuilder
    private var historyList: some View {
        #if os(iOS)
        List(selection: $selectedSessions) {
            historyListContent
        }
        .environment(\.editMode, $editMode)
        .searchable(text: $searchText, prompt: "Search conversations")
        .navigationTitle("History")
        .refreshable {
            await loadData()
        }
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !sessions.isEmpty {
                    editButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isEditing && !selectedSessions.isEmpty {
                    deleteSelectedButton
                }
            }
        }
        #else
        List {
            historyListContent
        }
        .searchable(text: $searchText, prompt: "Search conversations")
        .navigationTitle("History")
        .refreshable {
            await loadData()
        }
        #endif
    }

    @ViewBuilder
    private var historyListContent: some View {
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
                    isEditing: isEditing,
                    onTap: {
                        HapticManager.shared.lightTap()
                        Task {
                            await viewModel.switchToSession(id: session.id)
                        }
                    },
                    onDelete: {
                        sessionToDelete = session
                        showDeleteAlert = true
                    }
                )
                .tag(session.id)
            }
            #if os(iOS)
            .onDelete(perform: deleteSessions)
            #endif
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var editButton: some View {
        Button {
            HapticManager.shared.lightTap()
            withAnimation {
                editMode = isEditing ? .inactive : .active
            }
        } label: {
            Text(isEditing ? "Done" : "Select")
        }
        .foregroundStyle(ClarissaTheme.purple)
    }

    @ViewBuilder
    private var deleteSelectedButton: some View {
        Button(role: .destructive) {
            HapticManager.shared.warning()
            showDeleteConfirmation = true
        } label: {
            Text("Delete (\(selectedSessions.count))")
        }
    }
    #endif

    private func loadData() async {
        sessions = await viewModel.getAllSessions()
        currentSessionId = await viewModel.getCurrentSessionId()
    }

    #if os(iOS)
    private func deleteSessions(at offsets: IndexSet) {
        HapticManager.shared.warning()
        let sessionsToDelete = offsets.compactMap { index -> Session? in
            guard index < filteredSessions.count else { return nil }
            return filteredSessions[index]
        }
        for session in sessionsToDelete {
            sessions.removeAll { $0.id == session.id }
        }
        Task {
            for session in sessionsToDelete {
                await viewModel.deleteSession(id: session.id)
            }
        }
    }

    private func deleteSelectedSessions() {
        HapticManager.shared.warning()
        let idsToDelete = selectedSessions
        sessions.removeAll { idsToDelete.contains($0.id) }
        selectedSessions.removeAll()
        withAnimation {
            editMode = .inactive
        }
        Task {
            for id in idsToDelete {
                await viewModel.deleteSession(id: id)
            }
        }
    }
    #endif
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