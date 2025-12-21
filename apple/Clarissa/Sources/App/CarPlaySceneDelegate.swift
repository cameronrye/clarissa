#if canImport(CarPlay)
import CarPlay
import ClarissaKit
import UIKit

/// Handles CarPlay connection lifecycle and template management
/// Note: Requires com.apple.developer.carplay-assistant entitlement from Apple
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    // MARK: - Properties

    private var interfaceController: CPInterfaceController?
    private var carPlayViewModel: CarPlayViewModel?

    // MARK: - Scene Lifecycle

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        ClarissaLogger.ui.info("CarPlay connected")
        self.interfaceController = interfaceController

        // Create view model with voice capabilities
        let viewModel = CarPlayViewModel(interfaceController: interfaceController)
        self.carPlayViewModel = viewModel

        // Set up the root template
        Task { @MainActor in
            await viewModel.setupInitialTemplate()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnect interfaceController: CPInterfaceController
    ) {
        ClarissaLogger.ui.info("CarPlay disconnected")

        // Clean up resources
        Task { @MainActor in
            await carPlayViewModel?.cleanup()
        }

        self.interfaceController = nil
        self.carPlayViewModel = nil
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didSelect navigationAlert: CPNavigationAlert
    ) {
        // Handle navigation alerts if needed
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didSelect maneuver: CPManeuver
    ) {
        // Handle maneuvers if needed (not applicable for assistant)
    }
}
#endif

