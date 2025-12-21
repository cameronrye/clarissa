#if os(iOS)
import ClarissaKit
import SwiftUI
import UIKit

/// Main app scene delegate for iOS window management
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)

        // Create the SwiftUI view hierarchy
        let contentView = ContentView()
            .environmentObject(AppState.shared)

        window.rootViewController = UIHostingController(rootView: contentView)
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Clean up resources when scene is disconnected
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Resume any paused tasks
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Pause ongoing tasks
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Prepare UI for display
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Save state and release resources
    }
}
#endif

