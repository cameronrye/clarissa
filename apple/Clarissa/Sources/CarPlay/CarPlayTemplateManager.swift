#if canImport(CarPlay)
import CarPlay
import UIKit

/// Manages CarPlay template creation and presentation
/// Note: Driving Task apps can only use: CPListTemplate, CPGridTemplate,
/// CPInformationTemplate, CPTabBarTemplate, CPPointOfInterestTemplate
@MainActor
final class CarPlayTemplateManager {

    // MARK: - Properties

    private weak var interfaceController: CPInterfaceController?
    private weak var viewModel: CarPlayViewModel?
    private var rootTemplate: CPGridTemplate?

    // MARK: - Initialization

    init(interfaceController: CPInterfaceController, viewModel: CarPlayViewModel) {
        self.interfaceController = interfaceController
        self.viewModel = viewModel
    }

    // MARK: - Template Creation

    /// Show the main grid template with action buttons
    func showIdleTemplate() async {
        let gridTemplate = createMainGridTemplate()
        rootTemplate = gridTemplate

        do {
            try await interfaceController?.setRootTemplate(gridTemplate, animated: true)
        } catch {
            ClarissaLogger.ui.error("Failed to set idle template: \(error)")
        }
    }

    /// Show listening state using information template
    func showListeningTemplate() async {
        let infoTemplate = CPInformationTemplate(
            title: "Listening...",
            layout: .leading,
            items: [
                CPInformationItem(title: "Speak your question", detail: nil)
            ],
            actions: [
                CPTextButton(title: "Cancel", textStyle: .cancel) { [weak self] _ in
                    Task { @MainActor in
                        await self?.viewModel?.cancelListening()
                        await self?.showIdleTemplate()
                    }
                }
            ]
        )

        do {
            try await interfaceController?.setRootTemplate(infoTemplate, animated: true)
        } catch {
            ClarissaLogger.ui.error("Failed to set listening template: \(error)")
        }
    }

    /// Show processing state
    func showProcessingTemplate(query: String) async {
        let displayQuery = String(query.prefix(100))

        let infoTemplate = CPInformationTemplate(
            title: "Thinking...",
            layout: .leading,
            items: [
                CPInformationItem(title: "You asked", detail: displayQuery)
            ],
            actions: []
        )

        do {
            try await interfaceController?.setRootTemplate(infoTemplate, animated: true)
        } catch {
            ClarissaLogger.ui.error("Failed to set processing template: \(error)")
        }
    }

    /// Show response with speaking indicator
    func showSpeakingTemplate(response: String) async {
        let displayResponse = String(response.prefix(200))

        let infoTemplate = CPInformationTemplate(
            title: "Clarissa",
            layout: .leading,
            items: [
                CPInformationItem(title: nil, detail: displayResponse)
            ],
            actions: [
                CPTextButton(title: "Stop", textStyle: .cancel) { [weak self] _ in
                    Task { @MainActor in
                        self?.viewModel?.voiceManager.stopSpeaking()
                        await self?.showIdleTemplate()
                    }
                },
                CPTextButton(title: "Ask Again", textStyle: .normal) { [weak self] _ in
                    Task { @MainActor in
                        self?.viewModel?.voiceManager.stopSpeaking()
                        await self?.viewModel?.startListening()
                    }
                }
            ]
        )

        do {
            try await interfaceController?.setRootTemplate(infoTemplate, animated: true)
        } catch {
            ClarissaLogger.ui.error("Failed to set speaking template: \(error)")
        }

        // Return to idle when speaking finishes
        observeSpeechCompletion()
    }

    /// Show conversation history
    func showHistoryTemplate(conversations: [CarPlayViewModel.ConversationItem]) async {
        let items: [CPListItem] = conversations.map { item in
            let listItem = CPListItem(
                text: String(item.query.prefix(50)),
                detailText: String(item.response.prefix(80))
            )
            listItem.handler = { [weak self] _, completion in
                self?.viewModel?.voiceManager.speak(item.response)
                completion()
            }
            return listItem
        }

        let section = CPListSection(items: items, header: "Recent Conversations", sectionIndexTitle: nil)
        let listTemplate = CPListTemplate(title: "History", sections: [section])

        do {
            try await interfaceController?.pushTemplate(listTemplate, animated: true)
        } catch {
            ClarissaLogger.ui.error("Failed to show history: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func createMainGridTemplate() -> CPGridTemplate {
        let askButton = CPGridButton(
            titleVariants: ["Ask Clarissa"],
            image: UIImage(systemName: "mic.circle.fill") ?? UIImage()
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.viewModel?.startListening()
            }
        }

        let historyButton = CPGridButton(
            titleVariants: ["History"],
            image: UIImage(systemName: "clock.arrow.circlepath") ?? UIImage()
        ) { [weak self] _ in
            Task { @MainActor in
                guard let conversations = self?.viewModel?.conversationHistory else { return }
                await self?.showHistoryTemplate(conversations: conversations)
            }
        }

        return CPGridTemplate(
            title: "Clarissa",
            gridButtons: [askButton, historyButton]
        )
    }

    private func observeSpeechCompletion() {
        Task {
            while viewModel?.voiceManager.isSpeaking == true {
                try? await Task.sleep(for: .milliseconds(100))
            }
            await showIdleTemplate()
        }
    }
}
#endif

