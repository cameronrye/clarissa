import ClarissaKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

#if os(iOS)
import BackgroundTasks
import CarPlay
import UIKit

/// Background task identifier for memory sync
private let backgroundMemorySyncTaskId = "dev.rye.Clarissa.memorySync"

/// App delegate to handle CarPlay scene configuration and background tasks
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register background tasks
        registerBackgroundTasks()
        return true
    }

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

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundMemorySyncTaskId,
            using: nil
        ) { task in
            self.handleMemorySyncTask(task as! BGProcessingTask)
        }
    }

    private func handleMemorySyncTask(_ task: BGProcessingTask) {
        // Schedule next task
        scheduleMemorySyncTask()

        // Create async task to perform sync
        let syncTask = Task {
            await MemoryManager.shared.reload()
            task.setTaskCompleted(success: true)
        }

        // Handle expiration
        task.expirationHandler = {
            syncTask.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// Schedule background memory sync task
    func scheduleMemorySyncTask() {
        let request = BGProcessingTaskRequest(identifier: backgroundMemorySyncTaskId)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)  // 15 minutes

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            ClarissaLogger.agent.error("Failed to schedule background task: \(error.localizedDescription)")
        }
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
                // Start observing iCloud changes for memory sync across devices
                MemoryManager.shared.startObservingICloudChanges()

                // Prewarm Foundation Models at launch for faster first response
                // Community insight: "Call prewarm() when you're confident the user will use LLM features"
                await Self.prewarmFoundationModels()

                #if os(iOS)
                // Start Watch connectivity handler for Apple Watch integration
                WatchQueryHandler.shared.start()
                #endif
            }
            .onOpenURL { url in
                // Handle URL scheme for CLI integration
                // Supported: clarissa://ask?q=<question>, clarissa://new, clarissa://memory?action=sync
                appState.handleURL(url)
            }
            #if os(iOS)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                // Schedule background memory sync when app enters background
                appDelegate.scheduleMemorySyncTask()
            }
            #endif
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
