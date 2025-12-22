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

        // Default to main app scene
        let config = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = SceneDelegate.self
        return config
    }
}
#endif

@main
struct ClarissaApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    @StateObject private var appState = AppState()

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
    private static func prewarmFoundationModels() async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            guard SystemLanguageModel.default.availability == .available else { return }
            let session = LanguageModelSession()
            session.prewarm()
        }
        #endif
    }
}
