import ClarissaKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

#if os(macOS)
import AppKit

/// macOS App Delegate to handle dock icon clicks when window is closed
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    /// Called when user clicks dock icon - reopen main window if none visible
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // No visible windows - reopen the main window
            if let window = sender.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
#endif

#if os(iOS)
import BackgroundTasks
import UIKit

/// Background task identifier for memory sync
private let backgroundMemorySyncTaskId = "dev.rye.Clarissa.memorySync"

/// App delegate to handle background tasks
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register background tasks
        registerBackgroundTasks()
        return true
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundMemorySyncTaskId,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handleMemorySyncTask(processingTask)
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

    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var macAppDelegate
    #endif

    // Use shared AppState so Intents, URL handling, and UI all share one source of truth
    // Note: Using @ObservedObject since AppState.shared is already created elsewhere
    // @StateObject would create ownership confusion with the shared singleton
    @ObservedObject private var appState = AppState.shared

    /// Check if the app is running in screenshot/demo mode (for App Store screenshots)
    private static var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-SCREENSHOT_MODE")
    }

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

                #if os(macOS)
                // Resize window for App Store screenshots (1440x900)
                if Self.isScreenshotMode {
                    Self.resizeWindowForScreenshots()
                }
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
        // Use App Store screenshot size (1440x900) if in screenshot mode, otherwise default
        .defaultSize(
            width: Self.isScreenshotMode ? 1440 : 900,
            height: Self.isScreenshotMode ? 900 : 700
        )
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

                Divider()

                Button("Show History") {
                    NotificationCenter.default.post(name: .showHistory, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            }

            // Settings menu (for screenshot navigation)
            CommandMenu("Settings") {
                Button("General") {
                    openSettingsTab(.showSettingsGeneral)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Tools") {
                    openSettingsTab(.showSettingsTools)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Voice") {
                    openSettingsTab(.showSettingsVoice)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

                Button("Shortcuts") {
                    openSettingsTab(.showSettingsShortcuts)
                }
                .keyboardShortcut("4", modifiers: [.command, .option])

                Button("About") {
                    openSettingsTab(.showSettingsAbout)
                }
                .keyboardShortcut("5", modifiers: [.command, .option])
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

            // Window menu - add command to show main window
            CommandGroup(before: .windowList) {
                Button("Clarissa") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let window = NSApplication.shared.windows.first(where: { $0.title == "Clarissa" || $0.identifier?.rawValue.contains("main") == true }) {
                        window.makeKeyAndOrderFront(nil)
                    } else if let window = NSApplication.shared.windows.first {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()
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

    #if os(macOS)
    /// Resize the main window for App Store screenshots
    /// App Store accepts: 1280x800, 1440x900, 2560x1600, or 2880x1800
    @MainActor
    private static func resizeWindowForScreenshots() {
        guard let window = NSApplication.shared.windows.first else { return }
        // Set window size to 1440x900 (a required App Store dimension)
        let screenshotSize = NSSize(width: 1440, height: 900)
        window.setContentSize(screenshotSize)
        // Center the window on screen
        window.center()
    }

    /// Open the Settings window programmatically for screenshot mode
    @MainActor
    private static func openSettingsWindow() {
        // Use the standard macOS Settings action
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    #endif
}

// MARK: - Settings Menu Helpers

#if os(macOS)
/// Open Settings window and switch to a specific tab
/// Defined at module level to avoid MainActor isolation issues in Button actions
private func openSettingsTab(_ notification: Notification.Name) {
    Task { @MainActor in
        // Open Settings window using the standard macOS action
        if #available(macOS 14.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        // Post notification after delay to allow the window to load
        try? await Task.sleep(for: .milliseconds(300))
        NotificationCenter.default.post(name: notification, object: nil)
    }
}
#endif
