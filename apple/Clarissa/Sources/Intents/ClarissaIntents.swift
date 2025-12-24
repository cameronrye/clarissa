import AppIntents
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

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

        AppShortcut(
            intent: StartVoiceModeIntent(),
            phrases: [
                "Voice mode with \(.applicationName)",
                "Talk to \(.applicationName) with voice",
                "Start voice chat with \(.applicationName)"
            ],
            shortTitle: "Voice Mode",
            systemImageName: "waveform"
        )

        AppShortcut(
            intent: QuickQuestionIntent(),
            phrases: [
                "Quick question for \(.applicationName)",
                "Ask \(.applicationName) quickly"
            ],
            shortTitle: "Quick Question",
            systemImageName: "questionmark.bubble"
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

// MARK: - Start Voice Mode Intent

/// Intent for starting voice mode
@available(iOS 16.0, macOS 13.0, *)
struct StartVoiceModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Voice Mode"
    static let description = IntentDescription(
        "Start a voice conversation with Clarissa",
        categoryName: "Assistant"
    )

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let appState = AppState.shared
        appState.requestVoiceMode = true

        return .result(dialog: "Starting voice mode with Clarissa")
    }
}

// MARK: - Quick Question Intent

/// Intent for asking a quick question without opening the full app
@available(iOS 16.0, macOS 13.0, *)
struct QuickQuestionIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Question"
    static let description = IntentDescription(
        "Ask Clarissa a quick question",
        categoryName: "Assistant"
    )

    @Parameter(title: "Question")
    var question: String

    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let appState = AppState.shared

        if !question.isEmpty {
            appState.pendingShortcutQuestion = question
            appState.pendingQuestionSource = .siriShortcut
        }

        return .result(
            dialog: "Asking Clarissa...",
            view: ShortcutResultView(question: question)
        )
    }
}

// MARK: - Control Center Button Intent (iOS 18+)

/// A simple button intent for Control Center
@available(iOS 18.0, macOS 15.0, *)
struct OpenClarissaControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Clarissa"
    static let description = IntentDescription("Open Clarissa")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
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
