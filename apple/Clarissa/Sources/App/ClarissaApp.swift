import ClarissaKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

#if os(iOS)
import CarPlay
import UIKit

/// App delegate to handle CarPlay scene configuration
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // Check if this is a CarPlay scene
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(
                name: "CarPlay Configuration",
                sessionRole: .carTemplateApplication
            )
            config.delegateClass = CarPlaySceneDelegate.self
            return config
        }

        // Default configuration - SwiftUI handles the main app scene via WindowGroup
        return UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
    }
}
#endif

@main
struct ClarissaApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    // Use shared AppState so Intents, URL handling, and UI all share one source of truth
    // Note: Using @ObservedObject since AppState.shared is already created elsewhere
    // @StateObject would create ownership confusion with the shared singleton
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.isOnboardingComplete {
                    // Use MainTabView for iOS 26+ with tab bar minimization
                    // Falls back to ContentView for older OS versions
                    MainTabView()
                        .environmentObject(appState)
                } else {
                    OnboardingView()
                        .environmentObject(appState)
                }
            }
            .task {
                // Prewarm Foundation Models at launch for faster first response
                // Community insight: "Call prewarm() when you're confident the user will use LLM features"
                await Self.prewarmFoundationModels()
            }
            .onOpenURL { url in
                // Handle URL scheme for CLI integration
                // Supported: clarissa://ask?q=<question>, clarissa://new, clarissa://memory?action=sync
                appState.handleURL(url)
            }
        }
        #if os(macOS)
        .windowStyle(.automatic)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 700)
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    NotificationCenter.default.post(name: .newConversation, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // Edit menu additions
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Clear Conversation") {
                    NotificationCenter.default.post(name: .clearConversation, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }

            // View menu
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ToggleSidebar"),
                        object: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }

            // Voice menu
            CommandMenu("Voice") {
                Button("Start Voice Input") {
                    NotificationCenter.default.post(name: .toggleVoiceInput, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)

                Divider()

                Button("Read Last Response") {
                    NotificationCenter.default.post(name: .speakLastResponse, object: nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Stop Speaking") {
                    NotificationCenter.default.post(name: .stopSpeaking, object: nil)
                }
                .keyboardShortcut(".", modifiers: .command)
            }

            // Help menu
            CommandGroup(replacing: .help) {
                Link("Clarissa Documentation", destination: URL(string: "https://github.com/cameronrye/clarissa")!)
                Divider()
                Button("About Clarissa") {
                    NotificationCenter.default.post(name: .showAbout, object: nil)
                }
            }
        }
        #endif

        #if os(macOS)
        // Settings window for macOS
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #endif
    }

    /// Prewarm the Foundation Models session for faster first response
    /// Note: We prewarm the basic session here at app launch for initial model loading
    /// The actual chat session with tools will be prewarmed in ChatViewModel when provider is set up
    private static func prewarmFoundationModels() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else { return }
            // Create and prewarm a basic session to trigger model loading
            // The actual chat session with tools will be prewarmed in ChatViewModel
            let session = LanguageModelSession()
            session.prewarm()
        }
        #endif
    }
}
