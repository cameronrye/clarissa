import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var chatViewModel = ChatViewModel()
    @State private var showSettings = false
    @State private var showSessionHistory = false

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
                        settingsButton
                    }
                    #else
                    ToolbarItem(placement: .automatic) {
                        newSessionButton
                    }

                    ToolbarItem(placement: .automatic) {
                        historyButton
                    }

                    ToolbarItem(placement: .automatic) {
                        titleView
                    }

                    ToolbarItem(placement: .automatic) {
                        settingsButton
                    }
                    #endif
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(onProviderChange: {
                        chatViewModel.refreshProvider()
                    })
                }
                .sheet(isPresented: $showSessionHistory) {
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
    }

    private var titleView: some View {
        Text("Clarissa")
            .font(.headline.bold())
            .gradientForeground()
    }

    private var newSessionButton: some View {
        Button {
            chatViewModel.startNewSession()
        } label: {
            Image(systemName: "square.and.pencil")
                .foregroundStyle(ClarissaTheme.gradient)
        }
    }

    private var historyButton: some View {
        Button {
            showSessionHistory = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(ClarissaTheme.gradient)
        }
    }

    private var settingsButton: some View {
        Button {
            showSettings = true
        } label: {
            Image(systemName: "gear")
                .foregroundStyle(ClarissaTheme.gradient)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

