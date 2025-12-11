import ClarissaKit
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

@main
struct ClarissaApp: App {
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
        }
        #if os(macOS)
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {}
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
