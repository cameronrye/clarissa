import AppIntents
import Foundation

// MARK: - App Shortcuts Provider

/// Provides Siri Shortcuts for Clarissa
/// Automatically exposes key functionality to Shortcuts app and Siri
@available(iOS 16.0, macOS 13.0, *)
struct ClarissaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskClarissaIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) something",
                "Hey \(.applicationName)",
                "Talk to \(.applicationName)"
            ],
            shortTitle: "Ask Clarissa",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: StartNewConversationIntent(),
            phrases: [
                "Start new conversation with \(.applicationName)",
                "New chat with \(.applicationName)",
                "Reset \(.applicationName)"
            ],
            shortTitle: "New Conversation",
            systemImageName: "plus.bubble"
        )
    }
}

// MARK: - Ask Clarissa Intent

/// Intent for asking Clarissa a question via Siri
/// Example: "Hey Siri, ask Clarissa what's the weather today"
@available(iOS 16.0, macOS 13.0, *)
struct AskClarissaIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Clarissa"
    static let description = IntentDescription(
        "Ask Clarissa a question and get an intelligent response",
        categoryName: "Assistant"
    )

    /// The question to ask Clarissa
    @Parameter(title: "Question", description: "What would you like to ask Clarissa?")
    var question: String

    /// Open the app when running to show the conversation
    static let openAppWhenRun: Bool = true

    /// The result dialog shown after completion
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Get the shared AppState to send the message
        let appState = AppState.shared

        // If there's a question, set it as pending for the ChatView to process
        if !question.isEmpty {
            appState.pendingShortcutQuestion = question
            appState.pendingQuestionSource = .siriShortcut
        }

        return .result(
            dialog: "Opening Clarissa...",
            view: ShortcutResultView(question: question)
        )
    }
}

// MARK: - Start New Conversation Intent

/// Intent for starting a new conversation
@available(iOS 16.0, macOS 13.0, *)
struct StartNewConversationIntent: AppIntent {
    static let title: LocalizedStringResource = "New Conversation"
    static let description = IntentDescription(
        "Start a fresh conversation with Clarissa",
        categoryName: "Assistant"
    )

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Signal the app to start a new conversation
        let appState = AppState.shared
        appState.requestNewConversation = true

        return .result(dialog: "Starting a new conversation with Clarissa")
    }
}

// MARK: - Shortcut Result View

import SwiftUI

/// A simple view shown in the Shortcuts result
@available(iOS 16.0, macOS 13.0, *)
struct ShortcutResultView: View {
    let question: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(ClarissaTheme.gradient)
                Text("Clarissa")
                    .font(.headline)
            }

            if !question.isEmpty {
                Text("Asking: \(question)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready to assist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

